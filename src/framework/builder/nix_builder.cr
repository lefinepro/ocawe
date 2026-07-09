require "./builder"
require "file_utils"

module Ocawe
  module Builder
    # Unified NixBuilder — always builds through a nix multi-stage Dockerfile.
    # The final image is scratch by default, with a copied Nix store closure.
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
        FileUtils.rm_rf(context)
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
                File.chmod(dst, File.info(src).permissions.value)
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
          "RUN nix-channel --add https://nixos.org/channels/nixos-26.05 nixpkgs && nix-channel --update",
        ]

        runtime_packages = ["glibc", "zlib", "openssl", "libyaml", "pcre2", "libevent", "zstd", "sqlite", "gcc.cc.lib", "patchelf"]
        package_prefix = final_image == "scratch" ? "pkgsStatic" : "nixpkgs"
        effective_packages = if final_image == "scratch"
                               packages
                             else
                               (runtime_packages + packages).uniq
                             end

        if !effective_packages.empty?
          lines << "RUN nix-env -iA #{effective_packages.map { |pkg| "#{package_prefix}.#{pkg}" }.join(" ")}"
        end

        if final_image == "scratch" && !effective_packages.empty?
          lines << "RUN mkdir -p /nix-export && \\"
          lines << "  nix-store -q --requisites $(readlink -f /nix/var/nix/profiles/default) | \\"
          lines << "  xargs -I {} cp -r --parents {} /nix-export/ && \\"
          lines << "  cp -r --parents /nix/var /nix-export/ && \\"
          lines << "  mkdir -p /nix-export/lib64 && \\"
          lines << "  loader=$(find /nix-export/nix/store -path '*/lib/ld-linux-x86-64.so.2' | head -n1) && \\"
          lines << "  ln -s ${loader#/nix-export} /nix-export/lib64/ld-linux-x86-64.so.2 && \\"
          lines << "  mkdir -p /nix-export/lib && \\"
          lines << "  find /nix-export/nix/store -path '*/lib/*.so*' -exec sh -c 'for f do ln -sf ${f#/nix-export} /nix-export/lib/$(basename \"$f\"); done' sh {} +"
        end

        lines << ""
        lines << "# Stage 2: final image"
        lines << "FROM #{final_image}"

        if final_image == "scratch"
          lines << "COPY --from=nix-build /nix-export/nix /nix"
          lines << "COPY --from=nix-build /nix-export/lib64 /lib64"
          lines << "COPY --from=nix-build /nix-export/lib /lib"
        end
        lines << "ENV PATH=\"/nix/var/nix/profiles/default/bin:/nix/store:${PATH}\""
        lines << "ENV LD_LIBRARY_PATH=\"/nix/var/nix/profiles/default/lib:/nix/var/nix/profiles/default/lib64\""

        lines << "WORKDIR /app"
        lines << "COPY ocawecore /app/ocawecore"
        if final_image != "scratch"
          rpath = [
            "/nix/var/nix/profiles/default/lib",
            "/nix/store/8kvxvr3pmsypxiypq4g8zy13glnfr7nx-glibc-2.42-67/lib",
            "/nix/store/dbz6pb9g67kpgpl95k8d85kzpxm1c32p-zlib-1.3.2/lib",
            "/nix/store/l0vl4dali2mvbpi30a8da1f71jl85myg-openssl-3.6.2/lib",
            "/nix/store/iswwp0p9sa9iyiar387r423qhqpwpi4p-libyaml-0.2.5/lib",
            "/nix/store/x2zjc47pkhcwxr4iyv5xj3hdqfzfnyd9-pcre2-10.46/lib",
            "/nix/store/4c9lbyb7payh9akmia87v38bi82vdidb-libevent-2.1.12/lib",
            "/nix/store/fsvb5zrsm1n7m5wshm570imspffi7i8f-zstd-1.5.7/lib",
            "/nix/store/7nww4d4yl7jzf66qllvyn61xb21vp7ry-gcc-15.2.0-libgcc/lib",
          ].join(":")
          lines << "RUN sqlite_lib_dir=$(dirname $(find /nix/store -name libsqlite3.so.0 | head -n 1)) && patchelf --set-interpreter /nix/store/8kvxvr3pmsypxiypq4g8zy13glnfr7nx-glibc-2.42-67/lib64/ld-linux-x86-64.so.2 --set-rpath #{rpath}:$sqlite_lib_dir /app/ocawecore"
        end

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
          next if ignored_context_entry?(child)

          child_src = File.join(src, child)
          child_dst = File.join(dst, child)
          if File.directory?(child_src)
            copy_dir(child_src, child_dst)
          else
            File.open(child_src, "r") do |input|
              File.open(child_dst, "w") do |output|
                  IO.copy(input, output)
                end
                File.chmod(child_dst, File.info(child_src).permissions.value)
            end
          end
        end
      end

      private def ignored_context_entry?(name : String) : Bool
        [".git", ".turbo", ".next", "build", "dist", "coverage", "node_modules"].includes?(name)
      end
    end
  end
end
