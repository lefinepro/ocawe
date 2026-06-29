require "./builder"

module Ocawe
  module Builder
    # Unified NixBuilder — всегда собирает через nix multi-stage Dockerfile.
    # Финальный образ: scratch по умолчанию, либо указанный image.
    # Пакеты ставятся через pkgsStatic и копируются через nix store closure.
    class NixBuilder < Builder
      NIX_IMAGE = "nixos/nix:2.24.9"

      def initialize
        super("nix")
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

        dockerfile = generate_dockerfile(image: image, packages: packages, files: files)
        context = File.join(context_dir, "build")
        Dir.mkdir_p(context)
        File.write(File.join(context, "Dockerfile"), dockerfile)

        # Копируем бинарник
        copy_binary(binary_path, File.join(context, "ocawecore"))

        # Разрешаем файлы: явный список или все файлы в директории
        effective_files = if files.empty?
                            Dir.children(context_dir).select do |f|
                              path = File.join(context_dir, f)
                              File.file?(path) && !f.starts_with?('.') && f != "build"
                            end
                          else
                            files
                          end

        # Копируем файлы в контекст сборки
        effective_files.each do |file|
          src = File.join(context_dir, file)
          if File.exists?(src)
            dst = File.join(context, file)
            Dir.mkdir_p(File.dirname(dst))
            if File.directory?(src)
              copy_dir(src, dst)
            else
              File.open(src, "r") do |input|
                File.open(dst, "w") do |output|
                  IO.copy(input, output)
                end
              end
            end
          else
            STDERR.puts "Warning: file not found for copy: #{src}"
          end
        end

        image_arg = tag.empty? ? "ocawecore:latest" : tag
        run_build_command(runtime, context, image_arg)
      end

      def generate_dockerfile(
        image : String? = nil,
        packages : Array(String) = [] of String,
        files : Array(String) = [] of String
      ) : String
        final_image = image || "scratch"

        lines = [
          "# Stage 1: nix build environment",
          "FROM #{NIX_IMAGE} AS nix-build",
          "RUN nix-channel --update",
        ]

        # Генерируем nix expression для установки пакетов через pkgsStatic
        if !packages.empty?
          nix_expr = String.build do |io|
            io << "with import <nixpkgs> {}; let staticPkgs = pkgs.pkgsStatic; in "
            io << "buildEnv { name = \"ocawe-packages\"; paths = ["
            packages.each_with_index do |pkg, i|
              io << "staticPkgs.#{pkg}"
              io << " " unless i == packages.size - 1
            end
            io << "]; }"
          end
          lines << "RUN nix-env -i -E '" + nix_expr + "'"

          # Копируем nix store closure пакетов в /nix для финального образа
          lines << "RUN nix-store -q --requisites $(readlink -f /nix/var/nix/profiles/default) | \\"
          lines << "  xargs -I {} cp -r --parents {} /nix-export && \\"
          lines << "  cp -r --parents /nix/var /nix-export || true"
        end

        lines << ""
        lines << "# Stage 2: final image"
        lines << "FROM #{final_image}"

        # Копируем nix closure
        if !packages.empty?
          lines << "COPY --from=nix-build /nix-export/nix /nix"
          lines << "ENV PATH=\"/nix/var/nix/profiles/default/bin:/nix/store:${PATH}\""
        end

        # Копируем бинарник и файлы
        lines << "COPY ocawecore /app/ocawecore"
        lines << "RUN chmod +x /app/ocawecore"

        files.each do |file|
          lines << "COPY #{file} /app/#{file}"
        end

        lines << "EXPOSE 4111"
        lines << "ENTRYPOINT [\"/app/ocawecore\"]"
        lines << "CMD [\"--port\", \"4111\"]"

        lines.join("\n")
      end

      private def copy_dir(src : String, dst : String) : Nil
        Dir.mkdir_p(dst)
        Dir.children(src).each do |child|
          child_src = File.join(src, child)
          child_dst = File.join(dst, child)
          if File.directory?(child_src)
            copy_dir(child_src, child_dst)
          else
            File.open(child_src, "r") do |input|
              File.open(child_dst, "w") do |output|
                IO.copy(input, output)
              end
            end
          end
        end
      end
    end
  end
end
