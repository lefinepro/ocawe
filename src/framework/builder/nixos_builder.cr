require "./builder"

module Ocawe
  module Builder
    class NixOSBuilder < Builder
      NIX_IMAGE = "nixos/nix:2.24.9"

      def initialize
        super("nixos")
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
          "FROM #{NIX_IMAGE}",
          "RUN nix-channel --update",
        ]

        # Install nix packages
        lines << "RUN nix-env -iA nixpkgs.glibc"

        lines << "COPY ocawecore /app/ocawecore"
        lines << "RUN chmod +x /app/ocawecore"
        lines << "EXPOSE 4111"
        lines << "ENTRYPOINT [\"/app/ocawecore\"]"
        lines << "CMD [\"--port\", \"4111\"]"

        lines.join("\n")
      end
    end
  end
end
