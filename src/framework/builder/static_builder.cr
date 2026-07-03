require "./builder"

module Ocawe
  module Builder
    class StaticBuilder < Builder
      def initialize
        super("static")
      end

      def build(
        binary_path : String,
        tag : String = "",
        context_dir : String = ".",
        runtime : String = "docker",
        image : String? = nil,
        packages : Array(String) = [] of String,
        files : Array(String) = [] of String
      ) : Bool
        unless File.file?(binary_path)
          STDERR.puts "Error: binary not found: #{binary_path}"
          return false
        end

        dockerfile = generate_dockerfile
        context = File.join(context_dir, "build")
        Dir.mkdir_p(context)
        File.write(File.join(context, "Dockerfile"), dockerfile)

        # Copy binary into build context
        copy_binary(binary_path, File.join(context, "ocawecore"))

        image_arg = tag.empty? ? "ocawecore:latest" : tag
        run_build_command(runtime, context, image_arg)
      end

      private def generate_dockerfile : String
        # FROM scratch — минимальный образ, бинарник должен быть полностью статичным
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
