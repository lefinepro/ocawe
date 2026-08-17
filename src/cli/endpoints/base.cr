module OcaweCore
  module CLI
    class Main
      @project_root : String?
      @runtime_bin : String?

      private DEFAULT_PORT  = 4111
      private CORE_COMMANDS = Set{"build", "dev", "up", "shell", "exec", "test", "pull", "-v", "--version", "-h", "--help"}

      def initialize
      end

      def run(args : Array(String)) : Nil
        command = args.shift?

        case command
        when "build"
          build(args)
        when "dev"
          dev(args)
        when "up"
          up(args)
        when "shell"
          shell(args)
        when "exec"
          exec(args)
        when "test"
          test(args)
        when "pull"
          pull(args)
        when "-v", "--version"
          puts OcaweCore::VERSION
        when "-h", "--help"
          print_help
        else
          STDERR.puts "Unknown command: #{command}" if command
          print_help
          exit(1)
        end
      end

      private def print_help : Nil
        puts <<-TXT
          Usage: ocawe <command> [options]

          Commands:
            build [--release] [--static] [--output PATH]
                Build runtime binary.
            build SERVICE --remote HOST [--manager NAME]
                Build a Sireng service remotely and promote its runtime/image.
            dev [PATH] [-d] [--port N] [--log-level LEVEL]
                Build a development runtime and start server with live reload.
                PATH: optional workflow directory (default: current directory)
            up [PATH] [-d] [--port N] [--log-level LEVEL]
                Auto-build release runtime binary and start server.
                PATH: optional workflow directory (default: current directory)
                -d/--detach: run in background
                --log-level: debug, warning, or critical (default: warning)
            shell [PATH]
                Open an interactive shell inside the running workflow environment.
            exec [PATH] -- COMMAND [ARG...]
                Execute a command inside the running workflow environment.
            test [PATH]
                Run Cawfile test blocks against ORATOR_URL/OCAWE_TEST_BASE_URL.
            pull REF
                Clone or fast-forward pull a git Cawfile reference.
            -v, --version
                Print version.
            -h, --help
                Show this help.

          Remote Cawfile references:
            ocawe pull git+https://github.com/lefinepro/ocawe/caws/10-acp-agent
            ocawe pull git+ssh://github.com/lefinepro/ocawe/caws/10-acp-agent
            exec "github.com/lefinepro/ocawe/caws/10-acp-agent", runtime: {"git+https"}
            exec "git+ssh://github.com/lefinepro/ocawe/caws/10-acp-agent/10-acp-agent", runtime: {"git+ssh"}
        TXT
      end

      private def builtin_command?(command : String) : Bool
        CORE_COMMANDS.includes?(command)
      end

      private def project_root : String
        @project_root ||= begin
          root = installed_source_root || File.expand_path("../../..", __DIR__)
          File.expand_path(root)
        end
      end

      private def runtime_entry : String
        File.join(project_root, "src", "ocawe.cr")
      end

      private def runtime_bin : String
        @runtime_bin ||= begin
          candidates = [] of String
          if executable = Process.executable_path
            dir = File.dirname(executable)
            candidates << File.join(dir, "ocawecore")
            candidates << File.join(dir, ".ocawecore-wrapped")
            candidates << File.expand_path("../libexec/ocawecore", dir)
          end
          candidates << File.join(project_root, "build", "ocawecore")
          candidates.find { |path| executable_file?(path) } || candidates.last
        end
      end

      private def examples_root : String?
        candidates = [
          File.join(project_root, "caws"),
          File.expand_path("../caws", project_root),
        ]
        candidates.find { |path| Dir.exists?(path) }
      end

      private def installed_source_root : String?
        return nil unless executable = Process.executable_path

        source = File.expand_path("../share/ocawe/source", File.dirname(executable))
        File.file?(File.join(source, "src", "ocawe.cr")) ? source : nil
      end

      private def executable_file?(path : String) : Bool
        File.file?(path)
      end
    end
  end
end
