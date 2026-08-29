require "option_parser"
require "file_utils"
require "../../framework/discovery/cawfile_loader"
require "../../framework/discovery/git_https_puller"
require "../../framework/builder"
require "../remote_builder"

module OcaweCore
  module CLI
    # Credentials deliberately stay outside the image. A workflow container
    # receives only the authentication file from an existing Codex home; its
    # session/cache directory is an isolated writable tmpfs.
    module ContainerCredentials
      CODEX_HOME_TARGET = "/run/ocawe/credentials/codex"

      def self.arguments(environment : Hash(String, String)) : Array(String)
        source = environment["CODEX_HOME"]?.try(&.strip)
        return [] of String if source.nil? || source.empty?

        source_path = File.expand_path(source)
        auth_file = File.join(source_path, "auth.json")
        return [] of String unless File.file?(auth_file)

        [
          "--env", "CODEX_HOME=#{CODEX_HOME_TARGET}",
          "--tmpfs", CODEX_HOME_TARGET,
          "--volume", "#{auth_file}:#{File.join(CODEX_HOME_TARGET, "auth.json")}:ro",
        ]
      end
    end

    # Federation marketplace metadata belongs to the solver process, not to the
    # image.  Forward only the documented public declarations; credentials and
    # arbitrary host environment variables must never leak into a workflow
    # container.
    module ContainerFederationEnvironment
      FORWARDED_KEYS = [
        "OCAWE_FEDERATION_RESOURCE_CONFORMS_TO",
        "OCAWE_FEDERATION_ACTOR_NAME",
        "OCAWE_FEDERATION_ACTOR_SUMMARY",
        "OCAWE_FEDERATION_TAGS",
        "OCAWE_FEDERATION_SIGNATURES_REQUIRED",
      ]

      def self.arguments(environment : Hash(String, String)) : Array(String)
        arguments = [] of String
        FORWARDED_KEYS.each do |key|
          value = environment[key]?.try(&.strip)
          next if value.nil? || value.empty?
          arguments.concat(["--env", "#{key}=#{value}"])
        end
        arguments
      end
    end

    class Main
      private def build(args : Array(String)) : Nil
        remote_host = nil.as(String?)
        manager = "auto"
        base_image = "ocawe:latest"
        dry_run = false
        deploy = false
        namespace = "default"
        release = true
        static = false
        output = runtime_bin

        OptionParser.parse(args) do |parser|
          parser.on("--remote HOST", "Build a service on a remote host") { |value| remote_host = value }
          parser.on("--manager NAME", "Remote manager: auto, nerdctl, docker, or podman") { |value| manager = value }
          parser.on("--base-image IMAGE", "Remote runtime base image") { |value| base_image = value }
          parser.on("--dry-run", "Show the remote build without executing it") { dry_run = true }
          parser.on("--deploy", "Update the matching Kubernetes deployment after promotion") { deploy = true }
          parser.on("--namespace NAME", "Kubernetes namespace for --deploy (default: default)") { |value| namespace = value }
          parser.on("--release", "Build release binary (default)") { release = true }
          parser.on("--debug", "Build non-release binary") { release = false }
          parser.on("--static", "Build static binary") { static = true }
          parser.on("--output PATH", "Output binary path") { |v| output = v }
        end

        service = args.shift?
        if remote_host
          unless service
            STDERR.puts "Error: ocawe build --remote requires SERVICE"
            exit(1)
          end
          ok = RemoteBuilder.new(project_root).build(
            service,
            RemoteBuilder::Options.new(
              host: remote_host.not_nil!,
              manager: manager,
              base_image: base_image,
              deploy: deploy,
              namespace: namespace,
              dry_run: dry_run
            )
          )
          exit(1) unless ok
          return
        end
        if service
          STDERR.puts "Error: SERVICE builds require --remote HOST"
          exit(1)
        end

        abort_unless_success(build_runtime(release: release, static: static, output: output, force: true))
        build_rootfs_packer

        # Detect container configuration from Cawfile in current directory
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(Dir.current)
        if cawfile
          cawfile_bundle = ACD::Discovery::CawfileLoader.load(Dir.current, "root")
          if cawfile_bundle && cawfile_bundle.container && cawfile_bundle.container.not_nil!.configured?
            container_config = cawfile_bundle.container.not_nil!
            container_name = cawfile_bundle.name || cawfile_bundle.id
            container_tag = "#{container_name}:latest"
            base = case container_config.mode
                   when ACD::Discovery::ContainerMode::Static then "static"
                   when ACD::Discovery::ContainerMode::Nix    then "nix"
                   else                                            "static"
                   end

            abort_unless_success(build_container(
              binary_path: output,
              base: base,
              runtime: detect_runtime(allow_missing: true),
              tag: container_tag,
              image: container_config.image,
              packages: container_config.packages,
              files: container_config.files
            ))
          end
        end
      end

      private def detect_runtime(allow_missing : Bool = false) : String
        ["docker", "podman", "nerdctl"].each do |rt|
          return rt if runtime_available?(rt)
        end
        return "docker" if allow_missing
        STDERR.puts "Error: no container runtime found (docker, podman, nerdctl)"
        exit(1)
      end

      private def container_runtime_available? : Bool
        ["docker", "podman", "nerdctl"].any? { |rt| runtime_available?(rt) }
      end

      private def runtime_available?(runtime : String) : Bool
        return false unless system("command -v #{shell_quote(runtime)} > /dev/null 2>&1")

        Process.run(runtime, args: ["info"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
      end

      private def build_container(
        binary_path : String,
        base : String,
        runtime : String,
        tag : String,
        context_dir : String = Dir.current,
        image : String? = nil,
        packages : Array(String) = [] of String,
        files : Array(String) = [] of String,
      ) : Bool
        builder = Ocawe::Builder.builder_registry.resolve(base)
        builder.build(
          binary_path,
          tag: tag,
          context_dir: context_dir,
          runtime: runtime,
          image: image,
          packages: packages,
          files: files
        )
      rescue ex
        STDERR.puts "Error: #{ex.message}"
        false
      end

      private def dev(args : Array(String)) : Nil
        run_server(args, dev_mode: true)
      end

      private def up(args : Array(String)) : Nil
        run_server(args, dev_mode: false)
      end

      private def start(args : Array(String)) : Nil
        run_server(args, dev_mode: false, start_mode: true)
      end

      private def stop(args : Array(String)) : Nil
        workflows_root = resolve_workflows_root(args.shift?)
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(workflows_root)
        unless cawfile
          STDERR.puts "Error: no Cawfile found for #{workflows_root}"
          exit(1)
        end

        bundle = ACD::Discovery::CawfileLoader.load(workflows_root, "root")
        if bundle && bundle.container && bundle.container.not_nil!.configured? && container_runtime_available?
          stop_container(detect_runtime, container_name_for_bundle(bundle))
        else
          stop_local_runtime(workflows_root)
        end
      end

      private def run_server(args : Array(String), dev_mode : Bool, start_mode : Bool = false) : Nil
        port = nil
        detached = false
        log_level = nil.as(String?)

        OptionParser.parse(args) do |parser|
          parser.on("-d", "--detach", "Run in background (detach)") { detached = true }
          parser.on("--port PORT", "Runtime port (overrides Cawfile)") { |v| port = v.to_i }
          parser.on("--log-level LEVEL", "Log level: debug, warning, critical (overrides Cawfile)") { |v| log_level = v }
        end

        workflows_root = resolve_workflows_root(args.first?)
        FileUtils.mkdir_p(workflows_root)
        runtime_bin = runtime_bin()
        mode_name = start_mode ? "start" : (dev_mode ? "dev" : "up")
        puts "[ocawe] preparing #{mode_name} runtime binary=#{runtime_bin} workflows_root=#{workflows_root}"
        STDOUT.flush

        port ||= read_port_from_cawfile(workflows_root)

        # Detect container configuration from Cawfile
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(workflows_root)
        cawfile_bundle = nil
        container_config = nil
        if cawfile
          cawfile_bundle = ACD::Discovery::CawfileLoader.load(workflows_root, "root")
          container_config = cawfile_bundle.container if cawfile_bundle
        end

        if start_mode && !cawfile_bundle
          STDERR.puts "Error: ocawe start requires a Cawfile"
          exit(1)
        end

        if dev_mode
          Dir.cd(workflows_root) do
            abort_unless_success(build_runtime(release: false, output: runtime_bin))
          end
        elsif workflow_runtime_required?(cawfile_bundle)
          # A workflow can provide Crystal plugins (for example an inbox
          # handler).  Those are compiled into a workflow-specific entrypoint;
          # the packaged generic runtime cannot discover or load Crystal source
          # after it has started.  Build that entrypoint before baking the
          # container so the image executes the declared workflow, not only the
          # framework shell.
          workflow_runtime = File.join(Dir.tempdir, "ocawe-workflow-runtime-#{Process.pid}")
          Dir.cd(workflows_root) do
            abort_unless_success(build_runtime(release: true, output: workflow_runtime))
          end
          runtime_bin = workflow_runtime
        else
          abort_unless_success(ensure_runtime_binary(runtime_bin))
        end

        package_start_runtime(workflows_root, runtime_bin, cawfile_bundle.not_nil!) if start_mode

        container_tag = nil.as(String?)

        # Build container if container mode is specified
        if container_config && container_config.not_nil!.configured?
          container_name = cawfile_bundle.not_nil!.name || cawfile_bundle.not_nil!.id
          container_tag = "#{container_name}:latest"
          base = case container_config.mode
                 when ACD::Discovery::ContainerMode::Static then "static"
                 when ACD::Discovery::ContainerMode::Nix    then "nix"
                 else                                            "static"
                 end

          abort_unless_success(build_container(
            binary_path: runtime_bin,
            base: base,
            runtime: detect_runtime(allow_missing: true),
            tag: container_tag.not_nil!,
            context_dir: workflows_root,
            image: container_config.image,
            packages: container_config.packages,
            files: container_config.files
          ))
        end

        effective_port = (port || DEFAULT_PORT).not_nil!
        puts "[ocawe] starting #{mode_name} runtime port=#{effective_port} workflows_root=#{workflows_root}"
        STDOUT.flush
        runtime_args = ["--port=#{effective_port}"]
        runtime_args << "--start-mode" if start_mode
        runtime_command = nil.as(String?)
        if image = container_tag
          if container_runtime_available?
            runtime_args << "--log-level=#{log_level}" if log_level
            runtime_command = container_run_command(
              detect_runtime(allow_missing: true),
              image,
              container_name_for_bundle(cawfile_bundle.not_nil!),
              effective_port,
              container_workdir(dev_mode),
              runtime_args,
              mount_workflows_root: dev_mode ? workflows_root : nil
            )
          else
            puts "[ocawe] no container runtime available; starting local runtime instead"
            runtime_args << "--log-level=#{log_level}" if log_level
          end
        else
          runtime_args << "--log-level=#{log_level}" if log_level
        end

        if detached
          # Spawn the runtime as an independent background process. Previously this
          # used the now-unsupported `Process.fork`; spawning directly avoids the
          # deprecation and records the actual runtime PID (so `kill <pid>` works).
          runtime = spawn_runtime(runtime_command, runtime_bin, runtime_args, workflows_root)
          if start_mode && runtime_command
            puts "[ocawe] started container runtime in background (port #{port || DEFAULT_PORT})"
          else
            pid = runtime.pid
            pid_file = File.join(workflows_root, ".ocawe.pid")
            File.open(pid_file, "w") { |f| f.puts pid }
            puts "[ocawe] started in background (PID #{pid}, port #{port || DEFAULT_PORT})"
          end
          puts "[ocawe] dev live reload enabled" if dev_mode
          puts "[ocawe] logs: ocawe #{start_mode ? "start" : "up"} --follow"
          puts "[ocawe] stop: #{start_mode ? "ocawe stop" : "kill #{runtime.pid}"}"
        else
          runtime = spawn_runtime(runtime_command, runtime_bin, runtime_args, workflows_root)
          Signal::INT.trap do
            terminate(runtime)
            exit(0)
          end
          status = runtime.wait
          unless status.success?
            STDERR.puts "[ocawe] runtime exited"
            exit(1)
          end
        end
      end

      private def stop_container(runtime : String, container_name : String) : Nil
        output = IO::Memory.new
        status = Process.run(
          runtime,
          args: ["ps", "-q", "--filter", "name=^#{container_name}$"],
          output: output,
          error: Process::Redirect::Close,
        )
        unless status.success? && !output.to_s.strip.empty?
          puts "[ocawe] container not running: #{container_name}"
          return
        end

        stopped = Process.run(
          runtime,
          args: ["stop", "--time", "10", container_name],
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit,
        ).success?
        Process.run(
          runtime,
          args: ["rm", "-f", container_name],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close,
        )
        abort_unless_success(stopped)
        puts "[ocawe] stopped container: #{container_name}"
      end

      private def package_start_runtime(
        workflows_root : String,
        runtime_binary : String,
        bundle : ACD::Discovery::CawfileBundle,
      ) : String
        zstd_status = Process.run(
          "zstd",
          args: ["--version"],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close,
        )
        unless zstd_status.success?
          STDERR.puts "Error: zstd is required by `ocawe start`"
          exit(1)
        end

        package_root = File.join(Dir.tempdir, "ocawe-start-package-#{Process.pid}")
        build_root = File.join(workflows_root, "build")
        archive_base = File.join(build_root, "#{safe_runtime_name(bundle.id)}.runtime")
        tar_path = "#{archive_base}.tar"
        archive_path = "#{tar_path}.zst"

        FileUtils.rm_rf(package_root)
        FileUtils.mkdir_p(package_root)
        FileUtils.mkdir_p(build_root)

        FileUtils.cp(runtime_binary, File.join(package_root, "ocawecore"))
        cawfile_path = ACD::Discovery::CawfileLoader.find_cawfile(workflows_root)
        if cawfile_path
          FileUtils.cp(cawfile_path, File.join(package_root, File.basename(cawfile_path)))
        end

        ["agents", "skills", "tools"].each do |entry|
          source = File.join(workflows_root, entry)
          FileUtils.cp_r(source, File.join(package_root, entry)) if File.exists?(source)
        end

        if container = bundle.container
          container.files.each do |entry|
            next if ["agents", "skills", "tools"].includes?(entry)
            source = File.join(workflows_root, entry)
            next unless File.exists?(source)
            destination = File.join(package_root, entry)
            FileUtils.mkdir_p(File.dirname(destination))
            FileUtils.cp_r(source, destination)
          end
        end

        File.delete(tar_path) if File.exists?(tar_path)
        File.delete(archive_path) if File.exists?(archive_path)

        tar_status = Process.run(
          "tar",
          args: ["-C", package_root, "-cf", tar_path, "."],
          output: Process::Redirect::Close,
          error: Process::Redirect::Inherit,
        )
        abort_unless_success(tar_status.success?)

        zstd_status = Process.run(
          "zstd",
          args: ["-q", "-T0", "-f", tar_path, "-o", archive_path],
          output: Process::Redirect::Close,
          error: Process::Redirect::Inherit,
        )
        abort_unless_success(zstd_status.success?)
        File.delete(tar_path)
        puts "[ocawe] packaged runtime: #{archive_path}"
        archive_path
      ensure
        FileUtils.rm_rf(package_root) if package_root
      end

      private def safe_runtime_name(value : String) : String
        normalized = value.gsub(/[^a-zA-Z0-9_.-]/, "-")
        normalized.empty? ? "ocawe" : normalized
      end

      private def stop_local_runtime(workflows_root : String) : Nil
        pid_file = File.join(workflows_root, ".ocawe.pid")
        unless File.file?(pid_file)
          puts "[ocawe] no start-mode server found"
          return
        end

        pid = File.read(pid_file).strip.to_i
        Process.run(
          "kill",
          args: ["-TERM", pid.to_s],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close,
        )
        File.delete(pid_file)
        puts "[ocawe] stopped local server: #{pid}"
      rescue ex
        STDERR.puts "Error: unable to stop local server: #{ex.message}"
        exit(1)
      end

      private def shell(args : Array(String)) : Nil
        workflows_root = resolve_workflows_root(args.first?)
        container_name = container_name_for_workflows_root(workflows_root)
        command = container_exec_command(detect_runtime, container_name, ["bash"], interactive: true)
        abort_unless_success(run_interactive_cmd(command))
      end

      private def exec(args : Array(String)) : Nil
        workflow_path = nil.as(String?)
        if first = args.first?
          unless first == "--"
            workflow_path = args.shift
          end
        end
        args.shift if args.first? == "--"

        if args.empty?
          STDERR.puts "Error: ocawe exec requires COMMAND [ARG...]"
          exit(1)
        end

        workflows_root = resolve_workflows_root(workflow_path)
        container_name = container_name_for_workflows_root(workflows_root)
        command = container_exec_command(detect_runtime, container_name, args, interactive: false)
        abort_unless_success(run_interactive_cmd(command))
      end

      private def test(args : Array(String)) : Nil
        workflow_path = args.shift?
        workflows_root = resolve_workflows_root(workflow_path)
        bundle = ACD::Discovery::CawfileLoader.load_root(workflows_root)
        unless bundle
          STDERR.puts "Error: no Cawfile workflow found for #{workflows_root}"
          exit(1)
        end

        tests = bundle.tests
        if tests.empty?
          puts "[ocawe] no Cawfile tests found"
          return
        end

        runner = Ocawe::Testing::CawfileRunner.new(Ocawe::Testing::CawfileRunner.default_base_url)
        results = runner.run(bundle)
        failed = results.count { |result| !result.passed }
        results.each do |result|
          if result.passed
            puts "ok #{result.name} assert #{result.workflow_id}"
          else
            puts "not ok #{result.name} assert #{result.workflow_id}"
            puts "  expected: #{result.expected}"
            puts "  actual: #{result.actual}" unless result.actual.empty?
            puts "  missing tags: #{result.missing_tags.join(", ")}" unless result.missing_tags.empty?
            puts "  error: #{result.error}" if result.error
          end
        end
        exit(1) if failed > 0
      end

      private def pull(args : Array(String)) : Nil
        if args.empty?
          STDERR.puts "Error: ocawe pull requires REF"
          exit(1)
        end

        ref = args.first
        transport = git_transport_for_ref(ref)
        pulled = ACD::Discovery::GitHttpsPuller.new.pull(ref, transport)
        action = pulled.cloned ? "cloned" : "pulled"
        puts "[ocawe] #{action} #{pulled.repo_slug} via #{transport}"
        puts "[ocawe] local path: #{pulled.local_path}"
        if workflow_id = pulled.workflow_id
          puts "[ocawe] workflow: #{workflow_id}"
        end
        if Dir.exists?(pulled.local_path)
          if cawfile = ACD::Discovery::CawfileLoader.find_cawfile(pulled.local_path)
            puts "[ocawe] Cawfile: #{cawfile}"
          end
        end
      rescue ex
        STDERR.puts "Error: #{ex.message}"
        exit(1)
      end

      private def git_transport_for_ref(ref : String) : String
        stripped = ref.strip
        if stripped.starts_with?("git+ssh://")
          "git+ssh"
        else
          "git+https"
        end
      end

      private def read_port_from_cawfile(path : String) : Int32?
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(path)
        return nil unless cawfile

        raw = File.read(cawfile)
        lines = raw.lines
        lines.each_with_index do |line, idx|
          if line =~ /settings\s+do/
            port = nil
            lines[idx + 1..-1].each do |inner_line|
              break if inner_line =~ /^\s*end\s*$/
              if inner_line =~ /port\s*=\s*(\d+)/
                port = $1.to_i
                break
              end
            end
            return port if port
          end
        end
        nil
      rescue
        nil
      end

      private def container_workdir(dev_mode : Bool) : String
        dev_mode ? "/workspace" : "/app"
      end

      private def resolve_workflows_root(workflow_path : String?) : String
        if workflow_path
          candidates = [] of String
          candidates << File.expand_path(workflow_path, project_root)
          candidates << File.expand_path(workflow_path, Dir.current)

          if examples_root = examples_root()
            candidates << File.expand_path(workflow_path, examples_root)
            if workflow_path.starts_with?("caws/")
              candidates << File.expand_path(workflow_path.sub("caws/", ""), examples_root)
            end
          end

          if resolved = candidates.find { |path| ACD::Discovery::CawfileLoader.find_cawfile(path) }
            resolved
          else
            File.expand_path(workflow_path)
          end
        else
          Dir.current
        end
      end

      private def container_name_for_workflows_root(workflows_root : String) : String
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(workflows_root)
        unless cawfile
          STDERR.puts "Error: no Cawfile found for #{workflows_root}"
          exit(1)
        end

        cawfile_bundle = ACD::Discovery::CawfileLoader.load(workflows_root, "root")
        unless cawfile_bundle && cawfile_bundle.container
          STDERR.puts "Error: Cawfile at #{cawfile} has no `container do` configuration"
          exit(1)
        end

        container_name_for_bundle(cawfile_bundle)
      end

      private def container_name_for_bundle(cawfile_bundle) : String
        raw_name = cawfile_bundle.name || cawfile_bundle.id
        "ocawe-#{raw_name.gsub(/[^a-zA-Z0-9_.-]/, "-")}"
      end

      private def container_run_command(
        runtime : String,
        image : String,
        container_name : String,
        port : Int32,
        workdir : String,
        runtime_args : Array(String),
        mount_workflows_root : String? = nil,
      ) : String
        cleanup = [runtime, "rm", "-f", container_name].map { |part| shell_quote(part) }.join(" ")
        command = [runtime, "run", "--name", container_name, "--rm"]
        command.concat(ContainerCredentials.arguments(ENV.to_h))
        command.concat(ContainerFederationEnvironment.arguments(ENV.to_h))
        if mount = mount_workflows_root
          command.concat(["-v", "#{File.expand_path(mount)}:#{workdir}"])
        end
        command.concat(["-w", workdir])
        if ENV["OCAWE_CONTAINER_NETWORK"]? == "host"
          command << "--network" << "host"
        else
          command.concat(["-p", "#{port}:#{port}"])
        end
        # The generated image owns the runtime through its ENTRYPOINT.  Passing
        # /app/ocawecore again would make it the first runtime argument.
        command << image
        command.concat(runtime_args)
        "#{cleanup} >/dev/null 2>&1 || true; #{command.map { |part| shell_quote(part) }.join(" ")}"
      end

      private def container_exec_command(runtime : String, container_name : String, command_args : Array(String), interactive : Bool) : String
        command = [runtime, "exec"]
        command << "-it" if interactive
        command.concat(["-w", "/app", "-e", "HOME=/app/.meta/dev-server-context/home", container_name])
        command.concat(command_args)
        command.map { |part| shell_quote(part) }.join(" ")
      end

      private def shell_quote(value : String) : String
        "'" + value.gsub("'", "'\"'\"'") + "'"
      end

      private def build_runtime(release : Bool, static : Bool = false, output : String? = nil, force : Bool = false) : Bool
        output ||= runtime_bin
        flags = [] of String
        flags << "--release" if release
        flags << "--static" if static
        flags << "--no-debug" if release
        flag_str = flags.empty? ? "" : flags.join(" ") + " "
        entrypoint = build_runtime_entrypoint
        unless force
          sources = runtime_source_paths(entrypoint)
          if runtime_current?(output, sources)
            puts "[ocawe] using existing runtime: #{output}"
            return true
          end
        end

        # Check if crystal is available only when a rebuild is actually needed.
        unless system("command -v crystal > /dev/null 2>&1")
          STDERR.puts "Error: crystal compiler not found in PATH"
          STDERR.puts "Please install Crystal: https://crystal-lang.org/install/"
          return false
        end
        main_flag = entrypoint == runtime_entry ? "-D ocawe_runtime_main " : ""

        # Installed Nix packages keep the framework source read-only.  A
        # workflow-specific entrypoint still has to be compiled in that mode,
        # so use the writable workflow directory while keeping the output
        # outside the package.  Source checkouts retain the historical project
        # root build directory behaviour.
        build_directory = File.writable?(project_root) ? project_root : Dir.current
        Dir.cd(build_directory) do
          prefix = build_directory == project_root ? "mkdir -p build && " : ""
          run_cmd("#{prefix}crystal build #{entrypoint} #{main_flag}#{flag_str}-o #{output}")
        end
      end

      private def build_rootfs_packer : Bool
        source = File.join(project_root, "src", "tools", "rootfs_tar.c")
        output = File.join(project_root, "build", "rootfs_tar")
        return true unless File.file?(source)
        return true if File.file?(output) && File.info(output).modification_time >= File.info(source).modification_time
        return true unless system("command -v cc > /dev/null 2>&1")

        Dir.cd(project_root) do
          run_cmd("mkdir -p build && cc -Os -s -o #{shell_quote(output)} #{shell_quote(source)}")
        end
      end

      private def runtime_current?(output : String, sources : Array(String)) : Bool
        return false unless File.file?(output)
        output_mtime = File.info(output).modification_time
        sources.all? do |source|
          File.exists?(source) && File.info(source).modification_time <= output_mtime
        end
      end

      private def runtime_source_paths(entrypoint : String) : Array(String)
        sources = Dir.glob(File.join(project_root, "src", "**", "*.cr")).reject do |path|
          relative = Path[File.expand_path(path)].relative_to(Path[project_root]).to_s
          relative.starts_with?("src/cli/") || relative.starts_with?("src/framework/builder/")
        end
        sources.concat(Dir.glob(File.join(project_root, "shard.*")))
        sources << entrypoint
        if cawfile = ACD::Discovery::CawfileLoader.find_cawfile(Dir.current)
          sources << cawfile
        end
        sources.uniq
      end

      private def ensure_runtime_binary(output : String) : Bool
        if File.file?(output)
          puts "[ocawe] using existing runtime: #{output}"
          STDOUT.flush
          return true
        end

        unless system("command -v crystal > /dev/null 2>&1")
          STDERR.puts "Error: runtime binary not found: #{output}"
          STDERR.puts "Run `ocawe build --release` in an environment with Crystal, or install the packaged ocawe binary."
          return false
        end

        puts "[ocawe] building runtime: #{output}"
        STDOUT.flush
        Dir.cd(project_root) do
          run_cmd("mkdir -p build && crystal build #{runtime_entry} -D ocawe_runtime_main --release --no-debug -o #{output}")
        end
      end

      private def build_runtime_entrypoint : String
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(Dir.current)
        return runtime_entry unless cawfile

        cawfile_bundle = ACD::Discovery::CawfileLoader.load(Dir.current, "root")
        crystal_loader = cawfile_bundle.try(&.crystal_loader)
        return runtime_entry unless crystal_loader

        # Keep generated runtime glue outside the workflow tree.  A Cawfile is
        # the application source of truth; `ocawe up/run` must not leave a
        # project-owned build directory beside it.
        entrypoint = File.join(Dir.tempdir, "ocawe-runtime-entry-#{Process.pid}.cr")
        entrypoint_dir = File.dirname(entrypoint)
        lines = [] of String
        lines << %(require "#{require_path(entrypoint_dir, runtime_entry)}")
        crystal_loader.code.each do |line|
          lines << runtime_entry_line(line, entrypoint_dir)
        end
        crystal_loader.registry_files.each do |path|
          require_line = %(require "#{require_path(entrypoint_dir, path)}")
          lines << require_line unless lines.includes?(require_line)
        end
        lines << ""
        lines << "OcaweCore.run"
        FileUtils.mkdir_p(File.dirname(entrypoint))
        write_file_if_changed(entrypoint, lines.join("\n"))
        entrypoint
      end

      private def workflow_runtime_required?(bundle : ACD::Discovery::CawfileBundle?) : Bool
        bundle.try(&.crystal_loader).try(&.code.any?) ||
          bundle.try(&.crystal_loader).try(&.registry_files.any?) || false
      end

      private def runtime_entry_line(line : String, entrypoint_dir : String) : String
        stripped = line.strip
        if match = stripped.match(/^require\s+"([^"]+)"/)
          required = match[1]
          if required.starts_with?(".")
            target = File.expand_path(required, Dir.current)
            return %(require "#{require_path(entrypoint_dir, target)}")
          end
        end
        line
      end

      private def write_file_if_changed(path : String, content : String) : Nil
        return if File.exists?(path) && File.read(path) == content
        File.write(path, content)
      end

      private def require_path(from_dir : String, target : String) : String
        relative = Path[File.expand_path(target)].relative_to(Path[File.expand_path(from_dir)]).to_s
        relative = "./#{relative}" unless relative.starts_with?(".")
        relative.sub(/\.cr$/, "")
      end

      private def system(command : String) : Bool
        Process.run("sh", args: ["-c", command], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
      end

      private def spawn_cmd(command : String) : Process
        Process.new("bash", args: ["-c", command], input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      end

      private def spawn_runtime(command : String?, binary : String, args : Array(String), chdir : String) : Process
        if command
          spawn_cmd(command)
        else
          Process.new(binary, args: args, chdir: chdir, input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        end
      end

      private def run_cmd(command : String) : Bool
        status = Process.run("bash", args: ["-c", command], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        status.success?
      end

      private def run_interactive_cmd(command : String) : Bool
        status = Process.run("bash", args: ["-c", command], input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        status.success?
      end

      private def spawn_detached_cmd(command : String, log_file : String) : String
        output = IO::Memory.new
        status = Process.run(
          "bash",
          args: ["-c", "nohup #{command} > #{shell_quote(log_file)} 2>&1 < /dev/null & echo $!"],
          output: output,
          error: Process::Redirect::Inherit
        )
        abort_unless_success(status.success?)
        output.to_s.strip
      end

      private def abort_unless_success(ok : Bool) : Nil
        return if ok
        exit(1)
      end

      private def terminate(process : Process) : Nil
        process.terminate
      rescue
      end
    end
  end
end
