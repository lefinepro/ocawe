module Ocawe
  module Builder
    abstract class Builder
      getter base : String

      def initialize(@base : String)
      end

      abstract def build(binary_path : String, tag : String = "", context_dir : String = ".", runtime : String = "docker") : Bool

      protected def run_build_command(runtime : String, context : String, tag : String) : Bool
        cmd =
          case runtime.downcase
          when "podman"
            ["podman", "build", "-t", tag, context]
          when "nerdctl"
            ["nerdctl", "build", "-t", tag, context]
          else
            ["docker", "build", "-t", tag, context]
          end

        status = Process.run(cmd[0], args: cmd[1..-1], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        if status.success?
          puts "[ocawe] built image: #{tag}"
        else
          STDERR.puts "[ocawe] build failed: #{cmd.join(" ")}"
        end
        status.success?
      end
    end
  end
end
