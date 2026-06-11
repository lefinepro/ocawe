require "./builder"

module Ocawe
  module Builder
    abstract class Runtime
      getter name : String

      def initialize(@name : String)
      end

      abstract def build_image(dockerfile : String, context : String, tag : String) : Bool

      abstract def run_image(image : String, args : Array(String)? = nil) : Bool

      abstract def push_image(image : String) : Bool

      abstract def pull_image(image : String) : Bool

      # Check if the runtime binary is available
      abstract def check_availability! : Nil

      protected def run_command(command : Array(String)) : Bool
        status = Process.run(command[0], args: command[1..-1], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        status.success?
      end
    end

    class DockerRuntime < Runtime
      def initialize
        super("docker")
      end

      def check_availability! : Nil
        unless Process.run("sh", args: ["-c", "docker --version"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
          STDERR.puts "Error: docker not found in PATH"
          raise "docker runtime unavailable"
        end
      end

      def build_image(dockerfile : String, context : String, tag : String) : Bool
        check_availability!
        run_command(["docker", "build", "-t", tag, context])
      end

      def run_image(image : String, args : Array(String)? = nil) : Bool
        check_availability!
        command = args ? ["docker", "run", "--rm", image] + args : ["docker", "run", "--rm", image]
        run_command(command)
      end

      def push_image(image : String) : Bool
        check_availability!
        run_command(["docker", "push", image])
      end

      def pull_image(image : String) : Bool
        check_availability!
        run_command(["docker", "pull", image])
      end
    end

    class PodmanRuntime < Runtime
      def initialize
        super("podman")
      end

      def check_availability! : Nil
        unless Process.run("sh", args: ["-c", "podman --version"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
          STDERR.puts "Error: podman not found in PATH"
          raise "podman runtime unavailable"
        end
      end

      def build_image(dockerfile : String, context : String, tag : String) : Bool
        check_availability!
        run_command(["podman", "build", "-t", tag, context])
      end

      def run_image(image : String, args : Array(String)? = nil) : Bool
        check_availability!
        command = args ? ["podman", "run", "--rm", image] + args : ["podman", "run", "--rm", image]
        run_command(command)
      end

      def push_image(image : String) : Bool
        check_availability!
        run_command(["podman", "push", image])
      end

      def pull_image(image : String) : Bool
        check_availability!
        run_command(["podman", "pull", image])
      end
    end

    class NerdctlRuntime < Runtime
      def initialize
        super("nerdctl")
      end

      def check_availability! : Nil
        unless Process.run("sh", args: ["-c", "nerdctl --version"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
          STDERR.puts "Error: nerdctl not found in PATH"
          raise "nerdctl runtime unavailable"
        end
      end

      def build_image(dockerfile : String, context : String, tag : String) : Bool
        check_availability!
        run_command(["nerdctl", "build", "-t", tag, context])
      end

      def run_image(image : String, args : Array(String)? = nil) : Bool
        check_availability!
        command = args ? ["nerdctl", "run", "--rm", image] + args : ["nerdctl", "run", "--rm", image]
        run_command(command)
      end

      def push_image(image : String) : Bool
        check_availability!
        run_command(["nerdctl", "push", image])
      end

      def pull_image(image : String) : Bool
        check_availability!
        run_command(["nerdctl", "pull", image])
      end
    end

    class RuntimeRegistry
      def initialize
        @runtimes = {} of String => Runtime
        register(DockerRuntime.new)
        register(PodmanRuntime.new)
        register(NerdctlRuntime.new)
      end

      def register(runtime : Runtime) : Nil
        @runtimes[runtime.name] = runtime
      end

      def resolve(name : String) : Runtime
        @runtimes[name]? || raise "unsupported container runtime: #{name}"
      end

      def reset! : Nil
        @runtimes.clear
        register(DockerRuntime.new)
        register(PodmanRuntime.new)
        register(NerdctlRuntime.new)
      end
    end

    @@runtime_registry = RuntimeRegistry.new

    def self.runtime_registry : RuntimeRegistry
      @@runtime_registry
    end

    def self.reset_runtime_registry! : Nil
      @@runtime_registry.reset!
    end
  end
end
