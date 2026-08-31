require "base64"
require "digest/sha256"
require "file_utils"
require "http/client"
require "uri"

module ACD
  module Kemal
    class App
      private def process_aptok_inbox_activity(activity : Aptok::JsonMap) : Nil
        return if process_registered_aptok_inbox_activity(activity)

        remote_actor = activity["actor"]?.try(&.as_s?).to_s
        follow = if remote_actor.empty?
                   Aptok::JsonMap.new
                 else
                   @federation_kv.get("ocawe:federation:follow:#{remote_actor}").try { |raw| JSON.parse(raw).as_h } || Aptok::JsonMap.new
                 end
        process_polled_activity(follow, activity)
      end

      private def process_registered_aptok_inbox_activity(activity : Aptok::JsonMap) : Bool
        result = process_registered_aptok_inbox_result(activity)
        result.try(&.["handled"]?).try(&.as_bool?) || false
      end

      private def process_registered_aptok_inbox_result(activity : Aptok::JsonMap) : Hash(String, JSON::Any)?
        return nil unless Ocawe::Workflow.function_registry.registered?("ocawe_handle_aptok_inbox_activity")

        workflow_id = activity["workflow_id"]?.try(&.as_s?).to_s
        if workflow_id.empty?
          ids = workflow_ids
          workflow_id = ids.first if ids.size == 1
        end
        workflow_id = "server" if workflow_id.empty?

        input_data = {
          "activity" => JSON.parse(activity.to_json),
          "api"      => JSON.parse("federation".to_json),
        } of String => JSON::Any
        ctx = Ocawe::Workflow::NodeContext.new(
          workflow_id: workflow_id,
          run_id: "aptok-inbox-#{Random::Secure.hex(12)}",
          node_id: "ocawe_handle_aptok_inbox_activity",
          input_data: input_data,
          state: input_data,
        )
        result = Ocawe::Workflow.function_registry.call("ocawe_handle_aptok_inbox_activity", ctx)
        result
      rescue ex
        STDERR.puts "[ocawecore] registered inbox handler failed: #{ex.message}"
        nil
      end

      private def process_polled_activity(follow : Hash(String, JSON::Any), activity : Hash(String, JSON::Any)) : Bool
        activity_type = activity["type"]?.try(&.as_s?).to_s
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        status = follow["status"]?.try(&.as_s?).to_s
        local_actor = follow["local_actor"]?.try(&.as_s?).to_s
        local_actor = @settings.federation.local_actor if local_actor.empty?
        STDERR.puts "[federation] route activity=#{activity_type} status=#{status} id=#{activity["id"]?.try(&.as_s?)}"

        if activity_type == "Accept"
          update_aptok_follow_state(remote_actor, status: "active", error: "") unless remote_actor.empty?
          return true
        end

        unless status.empty? || status == "active" || status == "following"
          STDERR.puts "[federation] skip activity because follow status=#{status}"
          return false
        end
        unless activity_targets_local_actor?(activity, local_actor)
          STDERR.puts "[federation] ignore activity addressed to another solver"
          return true
        end
        ticket_payload = extract_ticket_activity_payload(activity)
        unless ticket_payload
          STDERR.puts "[federation] skip activity because no Ticket payload"
          return false
        end

        process_ticket_create_activity(follow, activity, ticket_payload[:ticket], ticket_payload[:activity_type])
      end

      private def activity_targets_local_actor?(activity : Hash(String, JSON::Any), local_actor : String) : Bool
        return true if local_actor.empty?
        audience = activity["to"]?
        return true unless audience

        recipients = if values = audience.as_a?
                       values.compact_map(&.as_s?)
                     elsif value = audience.as_s?
                       [value]
                     else
                       [] of String
                     end
        return true if recipients.empty?
        recipients.any? { |recipient| recipient.rstrip('/') == local_actor.rstrip('/') }
      end

      private def normalize_federation_activity(raw : String?) : String
        value = raw.to_s.strip.downcase
        return "merge" if value == "merge" || value == "mergerequest"
        "ticket"
      end

      private def federation_actor_from_node(node : JSON::Any?) : String
        return "" unless node
        if hash = node.as_h?
          return pick_first_non_empty(hash["id"]?.try(&.as_s?), hash["actor"]?.try(&.as_s?))
        end
        node.as_s? || ""
      end

      private def resolve_ticket_workflow_actor(body : Hash(String, JSON::Any), ticket : Hash(String, JSON::Any), local_domain : String, default_actor : String = "") : String
        assignee = ticket["assignee"]?
        attributed_to = ticket["attributedTo"]?
        workflow_actor = pick_first_non_empty(
          federation_actor_from_node(assignee),
          federation_actor_from_node(attributed_to),
          body["workflow_actor"]?.try(&.as_s?)
        )
        return workflow_actor unless workflow_actor.empty?
        workflow_id = pick_first_non_empty(body["workflow_id"]?.try(&.as_s?))
        return default_actor if workflow_id.empty?
        "#{local_domain}/actors/#{workflow_id}"
      end

      private def extract_ticket_activity_payload(activity : Hash(String, JSON::Any)) : NamedTuple(activity_type: String, ticket: Hash(String, JSON::Any))?
        activity_type = activity["type"]?.try(&.as_s?).to_s.strip
        return {activity_type: activity_type, ticket: activity} if activity_type == "Ticket"
        return nil unless activity_type == "Create" || activity_type == "Offer"
        ticket = activity["object"]?.try(&.as_h?) || {} of String => JSON::Any
        return nil unless ticket["type"]?.try(&.as_s?).to_s.strip.downcase == "ticket"
        {activity_type: activity_type, ticket: ticket}
      end

      private def ticket_has_offer_attachment?(ticket : Hash(String, JSON::Any)) : Bool
        attachment = ticket["attachment"]?
        if attachment_hash = attachment.try(&.as_h?)
          return attachment_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
        end
        attachments = attachment.try(&.as_a?) || [] of JSON::Any
        attachments.any? do |entry|
          next false unless entry_hash = entry.as_h?
          entry_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
        end
      end

      private def activity_reference(value : JSON::Any?) : String
        return "" unless value
        if value_hash = value.as_h?
          return pick_first_non_empty(value_hash["id"]?.try(&.as_s?), value_hash["context"]?.try(&.as_s?), value_hash["url"]?.try(&.as_s?))
        end
        value.as_s? || ""
      end

      private def ticket_offer_attachment_field(ticket : Hash(String, JSON::Any), field : String) : String
        attachment = ticket["attachment"]?
        if attachment_hash = attachment.try(&.as_h?)
          return activity_reference(attachment_hash[field]?)
        end
        attachments = attachment.try(&.as_a?) || [] of JSON::Any
        attachments.each do |entry|
          next unless entry_hash = entry.as_h?
          next unless entry_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
          return activity_reference(entry_hash[field]?)
        end
        ""
      end

      private def infer_ticket_workflow_activity(activity_doc : Hash(String, JSON::Any), ticket : Hash(String, JSON::Any), incoming_activity_type : String) : String
        explicit = normalize_federation_activity(ticket["activity"]?.try(&.as_s?) || activity_doc["activity"]?.try(&.as_s?))
        return explicit unless explicit == "ticket"
        return "merge" if incoming_activity_type == "Offer"
        return "merge" if ticket_has_offer_attachment?(ticket)
        "ticket"
      end

      private def process_ticket_create_activity(follow : Hash(String, JSON::Any), activity_doc : Hash(String, JSON::Any), ticket : Hash(String, JSON::Any), incoming_activity_type : String) : Bool
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        received_at = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
        local_actor = follow["local_actor"]?.try(&.as_s?).to_s
        local_actor = @settings.federation.local_actor if local_actor.empty?
        local_domain = local_domain_from_actor_url(local_actor)

        if project = ticket["ocawe_project"]?.try(&.as_h?)
          return process_ocawe_project_task(follow, activity_doc, ticket, project, local_actor, local_domain)
        end

        workflow_actor = resolve_ticket_workflow_actor(activity_doc, ticket, local_domain, local_actor)
        return false if workflow_actor.empty?

        workflow_id = "#{workflow_id_from_actor(workflow_actor)}"
        return false if workflow_id.empty?
        run_id = "federation-#{workflow_id}-#{Random.rand(UInt64).to_s(16)}"

        task = ticket["name"]?.try(&.as_s?) || ticket["summary"]?.try(&.as_s?) || ""
        return false if task.strip.empty?
        content = ticket["content"]?.try(&.as_s?) || ""
        activity = infer_ticket_workflow_activity(activity_doc, ticket, incoming_activity_type)
        repo_url = pick_first_non_empty(
          ticket["source"]?.try(&.as_s?),
          ticket_offer_attachment_field(ticket, "target"),
          ticket_offer_attachment_field(ticket, "origin"),
          activity_doc["repo_url"]?.try(&.as_s?)
        )
        repo_ref = activity_doc["repo_ref"]?.try(&.as_s?) || "main"
        provider = activity_doc["provider"]?.try(&.as_s?) || "acp-agent"
        ticket_id = ticket["id"]?.try(&.as_s?) || activity_doc["id"]?.try(&.as_s?) || ""

        suffix = Random.rand(UInt64::MAX).to_s(16)
        assign_activity = JSON.parse({
          "@context" => [Aptok::ACTIVITYSTREAMS_CONTEXT, Aptok::FORGEFED_CONTEXT],
          "id"       => "#{local_domain}/activities/assign-#{suffix}",
          "type"     => "Assign",
          "actor"    => workflow_actor,
          "object"   => JSON.parse(ticket.to_json),
          "target"   => workflow_actor,
        }.to_json).as_h
        append_aptok_outbox_event(workflow_actor, assign_activity, "outbox-assign-#{suffix}")

        input_data = {
          "input"            => JSON.parse(ticket.to_json),
          "task"             => JSON.parse(task.to_json),
          "content"          => JSON.parse(content.to_json),
          "ticket_id"        => JSON.parse(ticket_id.to_json),
          "ticket"           => JSON.parse(ticket.to_json),
          "repo_url"         => JSON.parse(repo_url.to_json),
          "repo_ref"         => JSON.parse(repo_ref.to_json),
          "provider"         => JSON.parse(provider.to_json),
          "remote_actor"     => JSON.parse(remote_actor.to_json),
          "local_actor"      => JSON.parse(local_actor.to_json),
          "workflow_actor"   => JSON.parse(workflow_actor.to_json),
          "api"              => JSON.parse("federation".to_json),
          "activity"         => JSON.parse(activity.to_json),
          "federation_input" => JSON.parse({
            "api"                    => "federation",
            "requested_activity"     => activity,
            "incoming_activity_type" => incoming_activity_type,
            "activity"               => activity_doc,
            "ticket"                 => ticket,
            "task"                   => task,
            "content"                => content,
            "ticket_id"              => ticket_id,
            "repo_url"               => repo_url,
            "repo_ref"               => repo_ref,
            "remote_actor"           => remote_actor,
            "local_actor"            => local_actor,
            "workflow_actor"         => workflow_actor,
          }.to_json),
        } of String => JSON::Any

        run_result = @workflow_service.start_run(workflow_id, run_id: run_id, input_data: input_data)
        run_output = run_result.output || {} of String => JSON::Any
        run_error = run_result.error.try(&.message).to_s
        STDERR.puts "[federation] ticket run workflow=#{workflow_id} run=#{run_result.run_id} status=#{run_result.status} error=#{run_error} output_keys=#{run_output.keys.join(",")}"
        publish_result_activity_from_output(
          workflow_id: workflow_id,
          run_id: run_result.run_id,
          run_status: run_result.status,
          output: run_output,
          ticket: ticket,
          requested_activity: "#{activity}",
          remote_actor: "#{remote_actor}",
          workflow_actor: "#{workflow_actor}",
          local_domain: "#{local_domain}",
          published_at: "#{received_at}",
        )
        true
      rescue ex
        error = ex.message || ex.class.name
        STDERR.puts "[federation] ticket route failed: #{error}"
        # A workflow/container failure is still a terminal federation result.
        # Without this Offer the sender keeps the accepted task in queued
        # forever, even though the one-shot container has already been removed.
        publish_result_activity_from_output(
          workflow_id: "#{workflow_id}",
          run_id: "#{run_id}",
          run_status: "failed",
          output: {
            "status"  => JSON.parse("failed".to_json),
            "error"   => JSON.parse(error.to_json),
            "message" => JSON.parse("Solver execution failed: #{error}".to_json),
          } of String => JSON::Any,
          ticket: ticket,
          requested_activity: "#{activity}",
          remote_actor: "#{remote_actor}",
          workflow_actor: "#{workflow_actor}",
          local_domain: "#{local_domain}",
          published_at: "#{received_at}",
        )
        false
      end

      # A remote `ocawe up --remote` sends the selected project as a compressed
      # archive in the Ticket. Run it locally on this server, using a child
      # ocawecore process so the received project gets its own Cawfile runtime.
      private def process_ocawe_project_task(
        follow : Hash(String, JSON::Any),
        activity_doc : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        project : Hash(String, JSON::Any),
        local_actor : String,
        local_domain : String,
      ) : Bool
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        remote_actor = activity_doc["actor"]?.try(&.as_s?).to_s if remote_actor.empty?
        workflow_id = "remote-project"
        run_id = "federation-remote-project-#{Random::Secure.hex(8)}"
        received_at = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
        workspace = File.join(Dir.current, ".ocawe", "federation-projects", "#{Time.utc.to_unix}-#{Random::Secure.hex(8)}")
        process = nil.as(Process?)

        begin
          encoded = project["content_base64"]?.try(&.as_s?).to_s
          raise "Ocawe project attachment is missing content_base64" if encoded.empty?
          archive_bytes = Base64.decode_string(encoded)
          expected_sha = project["sha256"]?.try(&.as_s?).to_s.strip
          if !expected_sha.empty? && Digest::SHA256.hexdigest(archive_bytes) != expected_sha
            raise "Ocawe project attachment checksum mismatch"
          end

          FileUtils.mkdir_p(workspace)
          # The sender currently uses this fixed name. Do not let an inbound
          # filename choose a path outside the isolated workspace.
          archive_path = File.join(workspace, "project.tar.zst")
          tar_path = File.join(workspace, "project.tar")
          File.open(archive_path, "wb") { |io| io.write(archive_bytes.to_slice) }

          unpack_ocawe_project!(archive_path, tar_path, workspace)
          bundle = ACD::Discovery::CawfileLoader.load(workspace, "root")
          raise "received Ocawe project has no loadable Cawfile" unless bundle
          workflow_id = bundle.not_nil!.id
          run_id = "federation-#{workflow_id}-#{Random::Secure.hex(8)}"

          binary = ENV["OCAWECORE_BINARY"]?.to_s
          binary = Process.executable_path.to_s if binary.empty?
          raise "remote project execution requires ocawecore or OCAWECORE_BINARY" if binary.empty? || !File.file?(binary)

          port = 20000 + Random.rand(20000)
          process = Process.new(
            binary,
            args: ["--port=#{port}"],
            chdir: workspace,
            env: {"OCAWE_WORKFLOWS_ROOT" => workspace},
            input: Process::Redirect::Close,
            output: Process::Redirect::Inherit,
            error: Process::Redirect::Inherit
          )
          wait_for_ocawe_project_runtime!(port)

          task = ticket["name"]?.try(&.as_s?) || ticket["summary"]?.try(&.as_s?) || "Run Ocawe project"
          content = ticket["content"]?.try(&.as_s?) || ""
          input_data = {
            "task"         => JSON.parse(task.to_json),
            "content"      => JSON.parse(content.to_json),
            "device_code"  => ticket["device_code"]? || JSON.parse("".to_json),
            "ticket"       => JSON.parse(ticket.to_json),
            "activity"     => JSON.parse(activity_doc.to_json),
            "remote_actor" => JSON.parse(remote_actor.to_json),
            "local_actor"  => JSON.parse(local_actor.to_json),
            "api"          => JSON.parse("federation".to_json),
          } of String => JSON::Any
          payload = {
            "run_id"     => JSON.parse(run_id.to_json),
            "input_data" => JSON.parse(input_data.to_json),
          } of String => JSON::Any
          path = "/v1/workflows/#{::URI.encode_path_segment(workflow_id)}/runs"
          response = ::HTTP::Client.post(
            "http://127.0.0.1:#{port}#{path}",
            headers: ::HTTP::Headers{"Content-Type" => "application/json"},
            body: payload.to_json
          )
          unless response.status_code >= 200 && response.status_code < 300
            raise "received Ocawe project failed HTTP #{response.status_code}: #{response.body}"
          end
          snapshot = JSON.parse(response.body).as_h?
          raise "received Ocawe project returned a non-object run response" unless snapshot
          status = snapshot.not_nil!["status"]?.try(&.as_s?).to_s
          status = "completed" if status.empty?
          output = snapshot.not_nil!["output"]?.try(&.as_h?) || {} of String => JSON::Any
          STDERR.puts "[federation] ran received project workflow=#{workflow_id} run=#{run_id} status=#{status}"
          publish_result_activity_from_output(
            workflow_id: workflow_id,
            run_id: run_id,
            run_status: status,
            output: output,
            ticket: ticket,
            requested_activity: "task",
            remote_actor: remote_actor,
            workflow_actor: local_actor,
            local_domain: local_domain,
            published_at: received_at,
          ) unless remote_actor.empty?
          true
        rescue ex
          error = ex.message || ex.class.name
          STDERR.puts "[federation] received Ocawe project failed: #{error}"
          publish_result_activity_from_output(
            workflow_id: workflow_id,
            run_id: run_id,
            run_status: "failed",
            output: {
              "status"  => JSON.parse("failed".to_json),
              "error"   => JSON.parse(error.to_json),
              "message" => JSON.parse("Received Ocawe project failed: #{error}".to_json),
            } of String => JSON::Any,
            ticket: ticket,
            requested_activity: "task",
            remote_actor: remote_actor,
            workflow_actor: local_actor,
            local_domain: local_domain,
            published_at: received_at,
          ) unless remote_actor.empty?
          false
        ensure
          terminate_ocawe_project_runtime(process) if process
          FileUtils.rm_rf(workspace)
        end
      end

      private def unpack_ocawe_project!(archive_path : String, tar_path : String, workspace : String) : Nil
        zstd_status = Process.run(
          "zstd",
          args: ["-q", "-d", "-f", archive_path, "-o", tar_path],
          output: Process::Redirect::Close,
          error: Process::Redirect::Inherit
        )
        raise "zstd could not decompress the received project" unless zstd_status.success?

        listing = IO::Memory.new
        tar_status = Process.run(
          "tar",
          args: ["-tf", tar_path],
          output: listing,
          error: Process::Redirect::Close
        )
        raise "tar could not inspect the received project" unless tar_status.success?
        listing.to_s.each_line do |entry|
          path = entry.strip.rstrip("/")
          parts = path.split("/")
          raise "received project archive contains an unsafe path" if path.starts_with?("/") || parts.includes?("..")
        end

        extract_status = Process.run(
          "tar",
          args: ["-C", workspace, "--no-same-owner", "--no-same-permissions", "--no-absolute-names", "-xf", tar_path],
          output: Process::Redirect::Close,
          error: Process::Redirect::Inherit
        )
        raise "tar could not unpack the received project" unless extract_status.success?
      end

      private def wait_for_ocawe_project_runtime!(port : Int32) : Nil
        deadline = Time.monotonic + 180.seconds
        loop do
          begin
            response = ::HTTP::Client.get("http://127.0.0.1:#{port}/health")
            return if response.status_code == 200
          rescue
          end
          raise "received Ocawe project runtime did not become healthy" if Time.monotonic > deadline
          sleep 100.milliseconds
        end
      end

      private def terminate_ocawe_project_runtime(process : Process) : Nil
        process.terminate
        process.wait
      rescue
      end

      private def workflow_id_from_actor(actor : String) : String
        return "" if actor.strip.empty?
        parts = actor.split('/').reject(&.empty?)
        return "" if parts.empty?
        actor_index = -1
        parts.each_with_index { |part, idx| actor_index = idx if part == "actors" }
        # The actor identifier is derived from the Cawfile `#+name:` header, which
        # need not match the workflow id, so an unknown identifier still routes to
        # the single workflow this runtime serves instead of being dropped.
        fallback = if actor_index >= 0 && actor_index + 1 < parts.size
                     parts[actor_index + 1]
                   else
                     parts.last? || ""
                   end
        ids = workflow_ids
        return fallback if fallback.empty? || ids.empty? || ids.includes?(fallback)
        return ids.first if ids.size == 1
        fallback
      end

      private def infer_queue_from_actor(remote_actor : String) : String
        tail = remote_actor.split('/').last?.to_s
        tail.empty? ? "order-queue" : tail
      end

      private def pick_first_non_empty(*values : String?) : String
        values.each do |value|
          next unless value
          stripped = value.strip
          return stripped unless stripped.empty?
        end
        ""
      end
    end
  end
end
