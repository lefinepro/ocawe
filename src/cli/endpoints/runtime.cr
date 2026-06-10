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

      private def up(args : Array(String)) : Nil
        port = nil
        detached = false
        log_level = nil.as(String?)
        workflow_path = nil.as(String?)

        OptionParser.parse(args) do |parser|
          parser.on("-d", "--detach", "Run in background (detach)") { detached = true }
          parser.on("--port PORT", "Runtime port (overrides Cawfile)") { |v| port = v.to_i }
          parser.on("--log-level LEVEL", "Log level: debug, warning, critical (overrides Cawfile)") { |v| log_level = v }
        end

        workflow_path = args.first?

        workflows_root = if workflow_path
                           expanded = File.expand_path(workflow_path, PROJECT_ROOT)
                           if ACD::Discovery::CawfileLoader.find_cawfile(expanded)
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
          io << " --log-level=#{log_level}" if log_level
        end

        if detached
          pid = Process.fork do
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

      private def build_runtime(release : Bool, static : Bool = false, output : String = RUNTIME_BIN) : Bool
        flags = [] of String
        flags << "--release" if release
        flags << "--static" if static
        flags << "--no-debug" if release
        flag_str = flags.empty? ? "" : flags.join(" ") + " "
        run_cmd("mkdir -p #{PROJECT_ROOT}/build && bash #{BOOTSTRAP_CRYSTAL} && crystal build #{RUNTIME_ENTRY} -D ocawe_runtime_main #{flag_str}-o #{output}")
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
