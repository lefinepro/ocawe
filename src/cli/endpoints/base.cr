module OcaweCore
  module CLI
    class Main
      private DEFAULT_PORT   = 4111
      private PROJECT_ROOT   = File.expand_path("../../..", __DIR__)
      private RUNTIME_ENTRY  = "#{PROJECT_ROOT}/src/ocawe.cr"
      private RUNTIME_BIN    = "#{PROJECT_ROOT}/build/ocawecore"
      private WORKFLOWS_PATH = "#{PROJECT_ROOT}/src/workflows"
      private CORE_COMMANDS  = Set{"build", "up", "shell", "exec", "pull", "-v", "--version", "-h", "--help"}

      def initialize
      end

      def run(args : Array(String)) : Nil
        command = args.shift?

        case command
        when "build"
          build(args)
        when "up"
          up(args)
        when "shell"
          shell(args)
        when "exec"
          exec(args)
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
                Auto-builds container from `container do` in Cawfile if present.
            up [PATH] [-d] [--port N] [--log-level LEVEL]
                Auto-build release runtime binary and start server.
                PATH: optional workflow directory (default: current directory)
                -d/--detach: run in background
                --log-level: debug, warning, or critical (default: warning)
            shell [PATH]
                Open an interactive shell inside the running workflow container.
            exec [PATH] -- COMMAND [ARG...]
                Execute a command inside the running workflow container.
            pull REF
                Clone or fast-forward pull a git Cawfile reference.
            -v, --version
                Print version.
            -h, --help
                Show this help.

          Container configuration in Cawfile:
            container do
              packages = ["git", "curl", "github:owner/tool"]
              files = ["agents", "skills", "tools"]
            end
            rootfs_tar --build PATH IMAGE_TAG  # low-memory rebuild from prepared build/container/rootfs

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
    end
  end
end
