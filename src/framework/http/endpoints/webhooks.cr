require "file_utils"
require "openssl/hmac"
require "uri"

module ACD
  module Kemal
    class App
      private def mount_webhook_endpoints
        return unless @settings.webhooks.enabled

        post "/v1/webhooks/cawfile" do |env|
          raw = env.request.body.try(&.gets_to_end).to_s
          unless verify_webhook_signature(raw, env.request.headers)
            next json_error(env, 403, "forbidden", "webhook signature verification failed")
          end

          body = JSON.parse(raw).as_h
          workflow_override = env.params.query["workflow"]?
          response = handle_cawfile_webhook(body, env.request.headers, workflow_override)
          env.response.status_code = 202
          env.response.content_type = "application/json"
          response.to_json
        rescue ex : JSON::ParseException
          json_error(env, 400, "bad_request", "invalid JSON webhook payload")
        rescue ex
          json_error(env, 422, "webhook_error", ex.message || "webhook processing failed")
        end

        get "/v1/webhooks/runs/:runId" do |env|
          run_id = env.params.url["runId"]
          snapshot = @webhook_run_lock.synchronize { @webhook_run_snapshots[run_id]? }
          unless snapshot
            next json_error(env, 404, "not_found", "webhook run not found: #{run_id}")
          end

          env.response.content_type = "application/json"
          snapshot.to_json
        end
      end

      private def handle_cawfile_webhook(
        body : Ocawe::Workflow::AnyHash,
        headers : ::HTTP::Headers,
        workflow_override : String? = nil,
      ) : Ocawe::Workflow::AnyHash
        event = webhook_event(headers)
        unless event.empty? || event == "push"
          return {
            "status" => json_any("ignored"),
            "event"  => json_any(event),
          } of String => JSON::Any
        end

        repository = body["repository"]?.try(&.as_h?) || raise "webhook payload missing repository"
        repo_name = repository["full_name"]?.try(&.as_s?) || repository["name"]?.try(&.as_s?) || raise "webhook repository missing full_name"
        clone_url = repository["ssh_url"]?.try(&.as_s?) || repository["clone_url"]?.try(&.as_s?) || raise "webhook repository missing clone_url"
        repo_key = webhook_repo_key(repository, clone_url, repo_name)
        ensure_webhook_repo_allowed!(repo_key)
        ref = body["ref"]?.try(&.as_s?) || ""
        unless webhook_ref_allowed?(ref)
          return {
            "status"     => json_any("ignored"),
            "event"      => json_any(event.empty? ? "push" : event),
            "repository" => json_any(repo_key),
            "ref"        => json_any(ref),
            "reason"     => json_any("ref not allowed"),
          } of String => JSON::Any
        end

        sha = body["after"]?.try(&.as_s?) || raise "webhook payload missing after sha"
        raise "webhook after sha is empty" if sha.strip.empty?

        checkout_dir = checkout_webhook_repo(repo_key, clone_url, sha)
        service_bundle = build_webhook_workflow_service(checkout_dir)
        workflow_id = select_webhook_workflow_id(
          workflow_override || body["workflow"]?.try(&.as_s?) || body["workflow_id"]?.try(&.as_s?),
          service_bundle[:workflow_ids]
        )
        delivery_id = webhook_delivery_id(headers)
        run_id = "webhook_#{sanitize_run_id(delivery_id.empty? ? sha[0, Math.min(12, sha.size)] : delivery_id)}"
        input_data = webhook_input_data(body, repo_key, event, delivery_id)

        queued_snapshot = {
          "status"      => json_any("queued"),
          "event"       => json_any(event.empty? ? "push" : event),
          "delivery_id" => json_any(delivery_id),
          "repository"  => json_any(repo_key),
          "ref"         => json_any(ref),
          "sha"         => json_any(sha),
          "workflow_id" => json_any(workflow_id),
          "run_id"      => json_any(run_id),
        } of String => JSON::Any
        @webhook_run_lock.synchronize { @webhook_run_snapshots[run_id] = JSON::Any.new(queued_snapshot) }

        spawn(name: "webhook-run-#{run_id}") do
          begin
            running_snapshot = queued_snapshot.merge({
              "status" => json_any("running"),
            })
            @webhook_run_lock.synchronize { @webhook_run_snapshots[run_id] = JSON::Any.new(running_snapshot) }

            run_result = service_bundle[:service].start_run(workflow_id, run_id: run_id, input_data: input_data)
            snapshot = service_bundle[:service].load_snapshot(workflow_id, run_result.run_id)
            snapshot_json = JSON.parse((snapshot.try(&.to_json) || "null"))
            @webhook_run_lock.synchronize { @webhook_run_snapshots[run_result.run_id] = snapshot_json }
          rescue ex
            failed_snapshot = queued_snapshot.merge({
              "status" => json_any("failed"),
              "error"  => json_any(ex.message || "webhook workflow failed"),
            })
            @webhook_run_lock.synchronize { @webhook_run_snapshots[run_id] = JSON::Any.new(failed_snapshot) }
          end
        end

        {
          "status"       => json_any("queued"),
          "event"        => json_any(event.empty? ? "push" : event),
          "delivery_id"  => json_any(delivery_id),
          "repository"   => json_any(repo_key),
          "ref"          => json_any(ref),
          "sha"          => json_any(sha),
          "workflow_id"  => json_any(workflow_id),
          "run_id"       => json_any(run_id),
          "status_url"   => json_any("/v1/webhooks/runs/#{run_id}"),
          "checkout_dir" => json_any(checkout_dir),
          "snapshot"     => JSON::Any.new(queued_snapshot),
        } of String => JSON::Any
      end

      private def verify_webhook_signature(payload : String, headers : ::HTTP::Headers) : Bool
        secret = ENV[@settings.webhooks.secret_env]?
        return false unless secret && !secret.empty?

        if signature = headers["X-Hub-Signature-256"]?
          expected = "sha256=#{webhook_hmac_sha256(secret, payload)}"
          return constant_time_equals?(expected, signature)
        end

        if signature = headers["X-Gitea-Signature"]?
          expected = webhook_hmac_sha256(secret, payload)
          return constant_time_equals?(expected, signature)
        end

        false
      end

      private def webhook_hmac_sha256(secret : String, payload : String) : String
        OpenSSL::HMAC.hexdigest(:sha256, secret, payload)
      end

      private def constant_time_equals?(left : String, right : String) : Bool
        return false unless left.bytesize == right.bytesize

        diff = 0
        left.each_byte.zip(right.each_byte) do |a, b|
          diff |= a ^ b
        end
        diff == 0
      end

      private def checkout_webhook_repo(repo_key : String, clone_url : String, sha : String) : String
        root = File.expand_path(@settings.webhooks.workspace_root)
        checkout_dir = File.join(root, safe_repo_path(repo_key))
        FileUtils.mkdir_p(File.dirname(checkout_dir))

        if Dir.exists?(File.join(checkout_dir, ".git"))
          run_webhook_git(["-C", checkout_dir, "fetch", "--all", "--prune"], "fetch #{repo_key}")
        else
          run_webhook_git(["clone", "--no-checkout", clone_url, checkout_dir], "clone #{repo_key}")
        end

        run_webhook_git(["-C", checkout_dir, "checkout", "--force", sha], "checkout #{repo_key}@#{sha}")
        run_webhook_git(["-C", checkout_dir, "clean", "-fdx"], "clean #{repo_key}")
        checkout_dir
      end

      private def run_webhook_git(args : Array(String), action : String) : Nil
        status = Process.run(
          "git",
          args: args,
          input: Process::Redirect::Close,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        raise "#{action} failed" unless status.success?
      rescue ex : File::NotFoundError
        raise "git executable not found; webhook runner requires git"
      end

      private def build_webhook_workflow_service(checkout_dir : String)
        locator = Discovery::WorkflowLocator.new(checkout_dir)
        bundles = locator.list_workflows
        raise "#{checkout_dir}: Cawfile has no workflow blocks" if bundles.empty?

        engine = Ocawe::Workflow::Engine.new
        agent_loader = Agents::Loader.new
        global_agents = agent_loader.load_dir(File.join(checkout_dir, "agents"))

        bundles.each do |bundle|
          loaded_agents = merge_agents(global_agents, agent_loader.load_dir(bundle.agents_dir))
          engine.register(load_workflow_definition(bundle, loaded_agents))
        end

        {
          service:      Ocawe::Workflow::Service.new(engine),
          workflow_ids: bundles.map(&.id),
        }
      end

      private def select_webhook_workflow_id(requested : String?, workflow_ids : Array(String)) : String
        if requested && !requested.strip.empty?
          id = requested.strip
          raise "unknown webhook workflow '#{id}'" unless workflow_ids.includes?(id)
          return id
        end

        if configured = @settings.webhooks.default_workflow
          id = configured.strip
          unless id.empty?
            raise "unknown default webhook workflow '#{id}'" unless workflow_ids.includes?(id)
            return id
          end
        end

        return workflow_ids.first if workflow_ids.size == 1
        raise "webhook Cawfile has multiple workflows (#{workflow_ids.join(", ")}); provide workflow"
      end

      private def webhook_input_data(body : Ocawe::Workflow::AnyHash, repo_key : String, event : String, delivery_id : String) : Ocawe::Workflow::AnyHash
        input = body.dup
        input["event"] = json_any(event.empty? ? "push" : event)
        input["delivery_id"] = json_any(delivery_id)
        input["repository_key"] = json_any(repo_key)
        input
      end

      private def ensure_webhook_repo_allowed!(repo_key : String) : Nil
        allowed = @settings.webhooks.allowed_repos
        return if allowed.empty?
        return if allowed.any? { |pattern| webhook_repo_allowed?(repo_key, pattern) }

        raise "repository not allowed for webhooks: #{repo_key}"
      end

      private def webhook_repo_allowed?(repo_key : String, pattern : String) : Bool
        simple_pattern_match?(repo_key, pattern)
      end

      private def webhook_ref_allowed?(ref : String) : Bool
        allowed = @settings.webhooks.allowed_refs
        return true if allowed.empty?
        allowed.any? { |pattern| simple_pattern_match?(ref, pattern) }
      end

      private def simple_pattern_match?(value : String, pattern : String) : Bool
        normalized = pattern.strip
        return false if normalized.empty?
        return true if normalized == value
        parts = normalized.split("*")
        return false if parts.size == 1

        cursor = 0
        unless normalized.starts_with?("*")
          first = parts.shift
          return false unless value.starts_with?(first)
          cursor = first.size
        end

        parts.each_with_index do |part, index|
          next if part.empty?
          found = value.index(part, cursor)
          return false unless found
          cursor = found + part.size
          if index == parts.size - 1 && !normalized.ends_with?("*")
            return false unless value.ends_with?(part)
          end
        end

        normalized.ends_with?("*") || cursor == value.size
      end

      private def webhook_repo_key(repository : Ocawe::Workflow::AnyHash, clone_url : String, repo_name : String) : String
        host = nil.as(String?)
        if html_url = repository["html_url"]?.try(&.as_s?)
          host = URI.parse(html_url).host
        end
        host ||= URI.parse(clone_url).host if clone_url.includes?("://")
        if !host && (match = clone_url.match(/^[^@]+@([^:]+):/))
          host = match[1]
        end
        host ||= "unknown"
        "#{host}/#{repo_name.sub(/\.git$/, "")}"
      rescue
        "unknown/#{repo_name.sub(/\.git$/, "")}"
      end

      private def webhook_event(headers : ::HTTP::Headers) : String
        headers["X-Gitea-Event"]? || headers["X-GitHub-Event"]? || headers["X-Gogs-Event"]? || ""
      end

      private def webhook_delivery_id(headers : ::HTTP::Headers) : String
        headers["X-Gitea-Delivery"]? || headers["X-GitHub-Delivery"]? || headers["X-Gogs-Delivery"]? || ""
      end

      private def safe_repo_path(repo_key : String) : String
        repo_key.split(/[\/:]/).reject(&.empty?).map { |part| part.gsub(/[^A-Za-z0-9_.-]/, "-") }.join("/")
      end

      private def sanitize_run_id(value : String) : String
        sanitized = value.gsub(/[^A-Za-z0-9_.-]/, "_")
        sanitized.empty? ? Random::Secure.hex(8) : sanitized
      end

      private def json_any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
