require "option_parser"

module CogniCore
  module CLI
    class Main
      private DEFAULT_PORT = 4111
      private RUNTIME_ENTRY = "../../src/cogni.cr"
      private RUNTIME_BIN = "../../build/cognicore"
      private DEV_RUNTIME_BIN = "../../build/cognicore-dev"
      private WORKFLOWS_PATH = "../../src/workflows"
      private AGENTS_PATH = "../../agents"
      private TOOLS_PATH = "../../tools"

      def run(args : Array(String)) : Nil
        command = args.shift?
        case command
        when "build"
          build(args)
        when "dev"
          dev(args)
        when "up"
          up(args)
        else
          print_help
          exit(1)
        end
      end

      private def print_help : Nil
        puts <<-TXT
Usage: cogni <command> [options]

Commands:
  build [--release] [--output PATH]
      Build runtime binary.
  dev [--port N] [--interval SECONDS]
      Watch workflows/global agents/tools, recompile and restart runtime in dev mode.
  up [--port N] [--workflows-root PATH] [--fallback-workflows-root PATH]
      Auto-build release runtime binary and start server.
        TXT
      end

      private def build(args : Array(String)) : Nil
        release = true
        output = RUNTIME_BIN

        OptionParser.parse(args) do |parser|
          parser.on("--release", "Build release binary (default)") { release = true }
          parser.on("--debug", "Build non-release binary") { release = false }
          parser.on("--output PATH", "Output binary path") { |v| output = v }
        end

        abort_unless_success(build_runtime(release: release, output: output))
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
        runtime = spawn_cmd("#{DEV_RUNTIME_BIN} --port #{port}")

        Signal::INT.trap do
          terminate(runtime)
          exit(0)
        end

        loop do
          sleep interval
          current = compute_fingerprint(tracked)
          next if current == fingerprint

          puts "[cogni] changes detected, recompiling runtime..."
          if build_runtime(release: false, output: DEV_RUNTIME_BIN)
            terminate(runtime)
            runtime = spawn_cmd("#{DEV_RUNTIME_BIN} --port #{port}")
            fingerprint = current
            puts "[cogni] runtime restarted"
          else
            STDERR.puts "[cogni] compile failed, keeping last runtime"
          end
        end
      end

      private def up(args : Array(String)) : Nil
        port = DEFAULT_PORT
        workflows_root = nil.as(String?)
        fallback_workflows_root = nil.as(String?)

        OptionParser.parse(args) do |parser|
          parser.on("--port PORT", "Runtime port") { |v| port = v.to_i }
          parser.on("--workflows-root PATH", "Preferred workflows root path") { |v| workflows_root = v }
          parser.on("--fallback-workflows-root PATH", "Fallback workflows root path") { |v| fallback_workflows_root = v }
        end

        abort_unless_success(build_runtime(release: true, output: RUNTIME_BIN))

        command = String.build do |io|
          io << RUNTIME_BIN
          io << " --port #{port}"
          io << " --workflows-root=#{workflows_root}" if workflows_root
          io << " --fallback-workflows-root=#{fallback_workflows_root}" if fallback_workflows_root
        end

        runtime = spawn_cmd(command)
        Signal::INT.trap do
          terminate(runtime)
          exit(0)
        end
        runtime.wait
      end

      private def build_runtime(release : Bool, output : String) : Bool
        release_flag = release ? "--release " : ""
        run_cmd("mkdir -p ../../build && crystal build #{RUNTIME_ENTRY} #{release_flag}-o #{output}")
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

CogniCore::CLI::Main.new.run(ARGV.dup)
