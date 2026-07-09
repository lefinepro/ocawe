require "option_parser"
require "../../framework/discovery/cawfile_loader"
require "../../framework/builder"

module OcaweCore
  module CLI
    class Main
      private def build(args : Array(String)) : Nil
        release = true
        static = false
        output = RUNTIME_BIN

        OptionParser.parse(args) do |parser|
          parser.on("--release", "Build release binary (default)") { release = true }
          parser.on("--debug", "Build non-release binary") { release = false }
          parser.on("--static", "Build static binary") { static = true }
          parser.on("--output PATH", "Output binary path") { |v| output = v }
        end

        abort_unless_success(build_runtime(release: release, static: static, output: output))

        # Detect container configuration from Cawfile in current directory
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(Dir.current)
        if cawfile
          cawfile_bundle = ACD::Discovery::CawfileLoader.load(Dir.current, "root")
          if cawfile_bundle && cawfile_bundle.container
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
              runtime: detect_runtime,
              tag: container_tag,
              image: container_config.image,
              packages: container_config.packages,
              files: container_config.files
            ))
          end
        end
      end

      private def detect_runtime : String
        ["docker", "podman", "nerdctl"].each do |rt|
          if Process.run("sh", args: ["-c", "command -v #{rt} > /dev/null 2>&1"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
            return rt
          end
        end
        STDERR.puts "Error: no container runtime found (docker, podman, nerdctl)"
        exit(1)
      end

      private def build_container(
        binary_path : String,
        base : String,
        runtime : String,
        tag : String,
        image : String? = nil,
        packages : Array(String) = [] of String,
        files : Array(String) = [] of String
      ) : Bool
        builder = Ocawe::Builder.builder_registry.resolve(base)
        builder.build(
          binary_path,
          tag: tag,
          context_dir: Dir.current,
          runtime: runtime,
          image: image,
          packages: packages,
          files: files
        )
      rescue ex
        STDERR.puts "Error: #{ex.message}"
        false
      end

      private def up(args : Array(String)) : Nil
        port = nil
        detached = false
        log_level = nil.as(String?)

        OptionParser.parse(args) do |parser|
          parser.on("-d", "--detach", "Run in background (detach)") { detached = true }
          parser.on("--port PORT", "Runtime port (overrides Cawfile)") { |v| port = v.to_i }
          parser.on("--log-level LEVEL", "Log level: debug, warning, critical (overrides Cawfile)") { |v| log_level = v }
        end

        workflows_root = resolve_workflows_root(args.first?)

        port ||= read_port_from_cawfile(workflows_root)

        # Detect container configuration from Cawfile
        cawfile = ACD::Discovery::CawfileLoader.find_cawfile(workflows_root)
        cawfile_bundle = nil
        container_config = nil
        if cawfile
          cawfile_bundle = ACD::Discovery::CawfileLoader.load(workflows_root, "root")
          container_config = cawfile_bundle.container if cawfile_bundle
        end

        abort_unless_success(build_runtime(release: true, output: RUNTIME_BIN))

        container_tag = nil.as(String?)

        # Build container if container mode is specified
        if container_config
          container_name = cawfile_bundle.not_nil!.name || cawfile_bundle.not_nil!.id
          container_tag = "#{container_name}:latest"
          base = case container_config.mode
                 when ACD::Discovery::ContainerMode::Static then "static"
                 when ACD::Discovery::ContainerMode::Nix    then "nix"
                 else                                            "static"
                 end

          abort_unless_success(build_container(
            binary_path: RUNTIME_BIN,
            base: base,
            runtime: detect_runtime,
            tag: container_tag.not_nil!,
            image: container_config.image,
            packages: container_config.packages,
            files: container_config.files
          ))
        end

        effective_port = (port || DEFAULT_PORT).not_nil!
        runtime_args = ["--port", "#{effective_port}"]
        if image = container_tag
          runtime_args << "--workflows-root=#{container_workflows_root(workflows_root)}"
          runtime_args << "--log-level=#{log_level}" if log_level
          command = container_run_command(detect_runtime, image, container_name_for_bundle(cawfile_bundle.not_nil!), effective_port, runtime_args)
        else
          runtime_args << "--workflows-root=#{workflows_root}"
          runtime_args << "--log-level=#{log_level}" if log_level
          command = ([RUNTIME_BIN] + runtime_args).map { |part| shell_quote(part) }.join(" ")
        end

        if detached
          # Spawn the runtime as an independent background process. Previously this
          # used the now-unsupported `Process.fork`; spawning directly avoids the
          # deprecation and records the actual runtime PID (so `kill <pid>` works).
          runtime = spawn_cmd(command)
          pid = runtime.pid

          pid_file = File.join(workflows_root, ".ocawe.pid")
          File.open(pid_file, "w") { |f| f.puts pid }

          puts "[ocawe] started in background (PID #{pid}, port #{port || DEFAULT_PORT})"
          puts "[ocawe] logs: ocawe up --follow"
          puts "[ocawe] stop: kill #{pid}"
        else
          runtime = spawn_cmd(command)
          Signal::INT.trap do
            terminate(runtime)
            exit(0)
          end
          runtime.wait
        end
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

      private def container_workflows_root(workflows_root : String) : String
        relative = Path[File.expand_path(workflows_root)].relative_to(Path[File.expand_path(Dir.current)]).to_s
        File.join("/app", relative)
      rescue
        "/app"
      end

      private def resolve_workflows_root(workflow_path : String?) : String
        if workflow_path
          expanded = File.expand_path(workflow_path, PROJECT_ROOT)
          if ACD::Discovery::CawfileLoader.find_cawfile(expanded)
            expanded
          else
            File.join(File.expand_path(Dir.current), workflow_path)
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
          STDERR.puts "Error: Cawfile at #{cawfile} has no @[Container] configuration"
          exit(1)
        end

        container_name_for_bundle(cawfile_bundle)
      end

      private def container_name_for_bundle(cawfile_bundle) : String
        raw_name = cawfile_bundle.name || cawfile_bundle.id
        "ocawe-#{raw_name.gsub(/[^a-zA-Z0-9_.-]/, "-")}"
      end

      private def container_run_command(runtime : String, image : String, container_name : String, port : Int32, runtime_args : Array(String)) : String
        cleanup = [runtime, "rm", "-f", container_name].map { |part| shell_quote(part) }.join(" ")
        command = [runtime, "run", "--name", container_name, "--rm", "-w", "/app", "-p", "#{port}:#{port}", image, "/app/ocawecore"]
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

      private def build_runtime(release : Bool, static : Bool = false, output : String = RUNTIME_BIN) : Bool
        # Check if crystal is available
        unless system("command -v crystal > /dev/null 2>&1")
          STDERR.puts "Error: crystal compiler not found in PATH"
          STDERR.puts "Please install Crystal: https://crystal-lang.org/install/"
          return false
        end

        flags = [] of String
        flags << "--release" if release
        flags << "--static" if static
        flags << "--no-debug" if release
        flag_str = flags.empty? ? "" : flags.join(" ") + " "
        entrypoint = build_runtime_entrypoint
        main_flag = entrypoint == RUNTIME_ENTRY ? "-D ocawe_runtime_main " : ""

        # Build from project root to ensure shard dependencies are found
        Dir.cd(PROJECT_ROOT) do
          run_cmd("mkdir -p build && crystal build #{entrypoint} #{main_flag}#{flag_str}-o #{output}")
        end
      end

      private def build_runtime_entrypoint : String
        cawfile_bundle = ACD::Discovery::CawfileLoader.load_root(Dir.current)
        crystal_loader = cawfile_bundle.try(&.crystal_loader)
        cawfile_code = crystal_loader.try(&.code) || [] of String
        registry_files = crystal_loader.try(&.registry_files) || [] of String
        return RUNTIME_ENTRY if cawfile_code.empty? && registry_files.empty?

        entrypoint = File.join(Dir.current, "build", "ocawe_runtime_entry.cr")
        Dir.mkdir_p(File.dirname(entrypoint))
        entrypoint_dir = File.dirname(entrypoint)
        File.write(entrypoint, String.build do |io|
          io << "require " << require_path(entrypoint_dir, RUNTIME_ENTRY).to_json << "\n"
          cawfile_code.each do |line|
            io << line << "\n"
          end
          registry_files.each do |registry_file|
            io << "require " << require_path(entrypoint_dir, registry_file).to_json << "\n"
          end
          io << "\nOcaweCore.run\n"
        end)
        entrypoint
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
        Process.new("bash", args: ["-lc", command], input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      end

      private def run_cmd(command : String) : Bool
        status = Process.run("bash", args: ["-lc", command], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        status.success?
      end

      private def run_interactive_cmd(command : String) : Bool
        status = Process.run("bash", args: ["-lc", command], input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        status.success?
      end

      private def spawn_detached_cmd(command : String, log_file : String) : String
        output = IO::Memory.new
        status = Process.run(
          "bash",
          args: ["-lc", "nohup #{command} > #{shell_quote(log_file)} 2>&1 < /dev/null & echo $!"],
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
