require "./builder"

module Ocawe
  module Builder
    class AlpineBuilder < Builder
      ALPINE_VERSION = "3.19"

      def initialize
        super("alpine")
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

        # Copy binary into build context
        copy_binary(binary_path, File.join(context, "ocawecore"))

        image_arg = tag.empty? ? "ocawecore:latest" : tag
        run_build_command(runtime, context, image_arg)
      end

      private def generate_dockerfile : String
        lines = [
          "FROM alpine:#{ALPINE_VERSION}",
          "",
          "RUN apk add --no-cache ca-certificates openssl",
          "",
          "COPY ocawecore /app/ocawecore",
          "RUN chmod +x /app/ocawecore",
          "",
          "EXPOSE 4111",
          "",
          "ENTRYPOINT [\"/app/ocawecore\"]",
          "CMD [\"--port\", \"4111\"]",
        ]
        lines.join("\n")
      end
    end
  end
end
