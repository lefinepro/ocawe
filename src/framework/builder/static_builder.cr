require "./builder"

module Ocawe
  module Builder
    class StaticBuilder < Builder
      def initialize
        super("static")
      end

      def build(binary_path : String, tag : String = "", context_dir : String = ".", runtime : String = "docker") : Bool
        unless File.file?(binary_path)
          STDERR.puts "Error: binary not found: #{binary_path}"
          return false
        end

        dockerfile = generate_dockerfile
        context = File.join(context_dir, "build")
        Dir.mkdir_p(context)
        File.write(File.join(context, "Dockerfile"), dockerfile)

        image_arg = tag.empty? ? "ocawecore:latest" : tag
        run_build_command(runtime, context, image_arg)
      end

      private def generate_dockerfile : String
        lines = [
          "FROM scratch",
          "COPY ocawecore /app/ocawecore",
          "EXPOSE 4111",
          "ENTRYPOINT [\"/app/ocawecore\"]",
          "CMD [\"--port\", \"4111\"]",
        ]
        lines.join("\n")
      end
    end
  end
end
