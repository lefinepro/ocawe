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
      end

      private def dev(args : Array(String)) : Nil
        port = DEFAULT_PORT
        interval = 1.0

        OptionParser.parse(args) do |parser|
          parser.on("--port PORT", "Runtime port") { |v| port = v.to_i }
          parser.on("--interval SECONDS", "Watch interval") { |v| interval = v.to_f }
        end

        tracked = [WORKFLOWS_PATH, AGENTS_PATH, TOOLS_PATH]
        fingerprint = compute_fingerprint(tracked)

        abort_unless_success(build_runtime(release: false, output: DEV_RUNTIME_BIN))
        runtime = spawn_cmd(dev_runtime_cmd(port))

        Signal::INT.trap do
          terminate(runtime)
          exit(0)
        end

        loop do
          sleep interval
          current = compute_fingerprint(tracked)
          next if current == fingerprint

          puts "[ocawe] changes detected, recompiling runtime..."
          if build_runtime(release: false, output: DEV_RUNTIME_BIN)
            terminate(runtime)
            runtime = spawn_cmd(dev_runtime_cmd(port))
            fingerprint = current
            puts "[ocawe] runtime restarted"
          else
            STDERR.puts "[ocawe] compile failed, keeping last runtime"
          end
        end
      end

      private def up(args : Array(String)) : Nil
        port = nil
        detached = false
        workflow_path = nil.as(String?)

        remaining = [] of String
        OptionParser.parse(args) do |parser|
          parser.on("-d", "--detach", "Run in background (detach)") { detached = true }
          parser.on("--port PORT", "Runtime port (overrides Cawfile)") { |v| port = v.to_i }
        end

        workflow_path = args.first?

        workflows_root = if workflow_path
          expanded = File.expand_path(workflow_path, PROJECT_ROOT)
          if CawfileLoader.find_cawfile(expanded)
            expanded
          else
            File.join(File.expand_path(Dir.current), workflow_path)
          end
        else
          Dir.current
        end

        port ||= read_port_from_cawfile(workflows_root)

        abort_unless_success(build_runtime(release: true, output: RUNTIME_BIN))

        command = String.build do |io|
          io << RUNTIME_BIN
          io << " --port #{port || DEFAULT_PORT}"
          io << " --workflows-root=#{workflows_root}"
        end

        if detached
          pid = Process.fork do
            Process.setsid
            runtime = spawn_cmd(command)
            runtime.wait
          end

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

      private def read_port_from_cawfile(path : String) : Int32?
        cawfile = CawfileLoader.find_cawfile(path)
        return nil unless cawfile

        raw = File.read(cawfile)
        raw.each_line do |line|
          if line =~ /settings\s+do/
            port = nil
            while line = raw.each_line.next?
              break if line =~ /^\s*end\s*$/
              if line =~ /port\s*=\s*(\d+)/
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

      private def build_runtime(release : Bool, static : Bool = false, output : String = RUNTIME_BIN) : Bool
        flags = [] of String
        flags << "--release" if release
        flags << "--static" if static
        flags << "--no-debug" if release
        flag_str = flags.empty? ? "" : flags.join(" ") + " "
        run_cmd("mkdir -p #{PROJECT_ROOT}/build && bash #{BOOTSTRAP_CRYSTAL} && crystal build #{RUNTIME_ENTRY} -D ocawe_runtime_main #{flag_str}-o #{output}")
      end

      private def dev_runtime_cmd(port : Int32) : String
        String.build do |io|
          io << DEV_RUNTIME_BIN
          io << " --port #{port}"
        end
      end

      private def compute_fingerprint(paths : Array(String)) : String
        entries = [] of String
        paths.each do |path|
          next unless Dir.exists?(path)
          Dir.glob("#{path}/**/*") do |file|
            next unless File.file?(file)
            info = File.info(file)
            entries << "#{file}:#{info.size}:#{info.modification_time.to_unix_ms}"
          end
        end
        entries.sort!
        entries.join("|")
      end

      private def spawn_cmd(command : String) : Process
        Process.new("bash", args: ["-lc", command], input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      end

      private def run_cmd(command : String) : Bool
        status = Process.run("bash", args: ["-lc", command], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        status.success?
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
