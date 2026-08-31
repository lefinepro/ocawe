require "file_utils"
require "random/secure"
require "base64"
require "digest/sha256"
require "aptok"

require "../framework/discovery/cawfile_loader"
require "../framework/federation/synchronous_delivery"

module OcaweCore
  module CLI
    # Sends the selected Cawfile as a ForgeFed task to an ActivityPub profile.
    # Remote `up` is a federation request; it never logs in to or executes on
    # the target host directly.
    class RemoteRunner
      record Options,
        profile : String,
        actor : String = "https://lefine.pro/actors/ocawe-device",
        dry_run : Bool = false

      def initialize(@project_root : String)
      end

      def up(selector : String, options : Options) : Bool
        workflow_root = resolve_workflow(selector)
        cawfile_path = ACD::Discovery::CawfileLoader.find_cawfile(workflow_root)
        raise "no Cawfile found in #{workflow_root}" unless cawfile_path
        bundle = ACD::Discovery::CawfileLoader.load(workflow_root, "root")
        raise "#{cawfile_path} could not be loaded" unless bundle

        handle = normalize_profile(options.profile)
        task_id = "#{options.actor}/activities/ocawe-task-#{Random::Secure.hex(12)}"
        device_code = "ocawe-#{Random::Secure.hex(16)}"
        tmp = File.join(Dir.tempdir, "ocawe-ap-task-#{Process.pid}-#{Time.utc.to_unix_ms}")
        FileUtils.mkdir_p(tmp)
        begin
          archive = package_project(workflow_root, tmp)
          archive_bytes = File.read(archive)
          target_actor, inbox = if options.dry_run
                                  {profile_actor(handle), ""}
                                else
                                  resolve_target(handle)
                                end
          activity = build_task(
            task_id: task_id,
            actor: options.actor,
            target_actor: target_actor,
            title: bundle.not_nil!.name || bundle.not_nil!.id,
            archive: archive_bytes,
            device_code: device_code
          )

          if options.dry_run
            puts "[ocawe] ActivityPub dry-run: would send #{File.basename(archive)} to #{handle}"
            puts "Archive: #{archive_bytes.bytesize} bytes"
            puts "Profile: #{target_actor}"
            puts "Task: #{task_id}"
            return true
          end

          delivery = Aptok::DeliveryConfig.new(
            inbox: inbox,
            actor: options.actor,
            target: target_actor,
            actor_ids: [target_actor]
          )
          response = Aptok::Transport.new.deliver_response!(delivery, activity)
          save_task(workflow_root, options, handle, target_actor, task_id, device_code)

          puts "Profile: #{target_actor}"
          puts "Task: #{task_id}"
          puts "Status: accepted (#{response.status_code})"
          true
        ensure
          FileUtils.rm_rf(tmp)
        end
      rescue ex
        STDERR.puts "[ocawe] ActivityPub remote up failed: #{ex.message || ex.class.name}"
        false
      end

      private def resolve_workflow(selector : String) : String
        candidates = [
          File.expand_path(File.join("pipelines", selector), Dir.current),
          File.expand_path(selector, Dir.current),
          File.expand_path(File.join("pipelines", selector), @project_root),
          File.expand_path(selector, @project_root),
        ]
        if resolved = candidates.find { |candidate| Dir.exists?(candidate) && File.file?(File.join(candidate, "Cawfile")) }
          return resolved
        end
        raise "workflow '#{selector}' not found; expected #{selector}/Cawfile or pipelines/#{selector}/Cawfile"
      end

      private def normalize_profile(value : String) : String
        raw = value.strip
        raw = raw[1..] if raw.starts_with?("@")
        parts = raw.split("@")
        raise "remote profile must use @handle@domain" unless parts.size == 2 && !parts[0].empty? && !parts[1].empty?
        "@#{parts[0]}@#{parts[1]}"
      end

      private def resolve_target(handle : String) : Tuple(String, String)
        normalized = handle[1..]
        webfinger = Aptok::Remote.lookup_webfinger("acct:#{normalized}", Aptok::Remote.default_document_loader)
        raise "profile not found through WebFinger: #{handle}" unless webfinger

        actor_url = webfinger_self_link(webfinger)
        raise "profile has no ActivityPub actor link: #{handle}" if actor_url.empty?
        actor = Aptok::Remote.default_document_loader.call(actor_url)
        raise "profile actor could not be loaded: #{actor_url}" unless actor
        inbox = actor["inbox"]?.try(&.as_s?).to_s
        raise "profile actor has no inbox: #{actor_url}" if inbox.empty?
        {actor_url, inbox}
      end

      private def profile_actor(handle : String) : String
        name, domain = handle[1..].split("@")
        "https://#{domain}/actors/#{name}"
      end

      private def package_project(workflow_root : String, tmp : String) : String
        staging = File.join(tmp, "project")
        copy_tree(workflow_root, staging)
        tar_path = File.join(tmp, "project.tar")
        archive = File.join(tmp, "project.tar.zst")
        run!("tar", ["-C", staging, "--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "-cf", tar_path, "."])
        run!("zstd", ["-q", "-f", tar_path, "-o", archive])
        archive
      end

      private def copy_tree(source : String, target : String) : Nil
        FileUtils.mkdir_p(target)
        Dir.children(source).each do |name|
          next if {".git", ".ocawe", ".env", "build", "node_modules", ".pnpm-store", "dist", "target", "coverage"}.includes?(name)
          next if name.starts_with?(".env.") || name.ends_with?(".pem")

          source_path = File.join(source, name)
          target_path = File.join(target, name)
          next if File.symlink?(source_path)
          if Dir.exists?(source_path)
            copy_tree(source_path, target_path)
          else
            FileUtils.cp(source_path, target_path)
          end
        end
      end

      private def webfinger_self_link(document : Aptok::JsonMap) : String
        links = document["links"]?.try(&.as_a?) || [] of JSON::Any
        link = links.find do |entry|
          map = entry.as_h?
          next false unless map
          map["rel"]?.try(&.as_s?) == "self" && map["href"]?.try(&.as_s?)
        end
        link.try(&.as_h["href"]?.try(&.as_s?)).to_s
      end

      private def build_task(
        task_id : String,
        actor : String,
        target_actor : String,
        title : String,
        archive : String,
        device_code : String,
      ) : Aptok::JsonMap
        request = Aptok::PublishRequest.new(
          title: "Run Ocawe Cawfile: #{title}",
          content: "Run the attached Ocawe project archive on this profile.",
          assignee: target_actor,
          attributed_to: actor
        )
        delivery = Aptok::DeliveryConfig.new(
          inbox: "",
          actor: actor,
          target: target_actor,
          actor_ids: [target_actor]
        )
        activity = Aptok::Transport.new.build_forgefed_ticket_create(request, delivery)
        ticket = activity["object"].as_h
        ticket["activity"] = JSON.parse("task".to_json)
        ticket["ocawe_project"] = JSON.parse({
          "filename"       => "project.tar.zst",
          "media_type"     => "application/zstd",
          "sha256"         => Digest::SHA256.hexdigest(archive),
          "content_base64" => Base64.strict_encode(archive),
        }.to_json)
        ticket["device_code"] = JSON.parse(device_code.to_json)
        activity["id"] = JSON.parse(task_id.to_json)
        activity
      end

      private def run!(program : String, args : Array(String)) : Nil
        status = Process.run(program, args: args, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        raise "#{program} exited with status #{status.exit_code}" unless status.success?
      end

      private def save_task(workflow_root : String, options : Options, handle : String, target_actor : String, task_id : String, device_code : String) : Nil
        storage_dir = File.join(workflow_root, ".ocawe")
        storage_path = File.join(storage_dir, "remote-task.json")
        FileUtils.mkdir_p(storage_dir)
        File.write(storage_path, {
          "profile"      => handle,
          "target_actor" => target_actor,
          "sender_actor" => options.actor,
          "task_id"      => task_id,
          "device_code"  => device_code,
          "updated_at"   => Time.utc.to_s,
        }.to_json)
        File.chmod(storage_path, 0o600)
      end
    end
  end
end
