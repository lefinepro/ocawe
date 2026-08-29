require "file_utils"
require "./builder"

module Ocawe
  module Builder
    # Fast workflow image builder. Historical name is kept because Cawfile
    # package-backed containers still resolve to ContainerMode::Nix.
    class NixBuilder < Builder
      IGNORED_CONTEXT_ENTRIES = [".git", ".turbo", ".next", "build", "dist", "coverage", "node_modules"]

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
        files : Array(String) = [] of String,
      ) : Bool
        unless File.file?(binary_path)
          STDERR.puts "Error: binary not found: #{binary_path}"
          return false
        end

        runtime_binary = unwrap_runtime_binary(binary_path)

        context = File.join(context_dir, "build", "container")
        FileUtils.rm_rf(context)
        Dir.mkdir_p(context)
        rootfs = File.join(context, "rootfs")
        Dir.mkdir_p(rootfs)

        copy_executable(runtime_binary, File.join(rootfs, "app", "ocawecore"))
        copy_binary_closure(runtime_binary, rootfs)
        copy_package_tools(packages, rootfs)
        copy_default_tools(rootfs)
        write_runtime_entrypoint(rootfs)
        copied_workflow_config = copy_workflow_cawfile(context_dir, rootfs)

        dockerfile = generate_dockerfile(image: image, packages: packages, files: files)
        File.write(File.join(context, "Dockerfile"), dockerfile)

        effective_files = if files.empty?
                            Dir.children(context_dir).select do |f|
                              path = File.join(context_dir, f)
                              File.exists?(path) && !f.starts_with?('.') && !ignored_context_entry?(f)
                            end
                          else
                            files.dup
                          end

        # Function plugins are executable application source, not optional
        # documentation assets. Include them even when a project supplies an
        # explicit allowlist so release images cannot silently omit functions.
        function_plugins = File.join(context_dir, "plugins", "functions")
        if Dir.exists?(function_plugins) && !effective_files.includes?("plugins/functions")
          effective_files << "plugins/functions"
        end
        legacy_plugins = File.join(context_dir, "plugins", "commands")
        if Dir.exists?(legacy_plugins) && !effective_files.includes?("plugins/commands")
          effective_files << "plugins/commands"
        end

        # Копируем файлы в контекст сборки
        effective_files.each do |file|
          next if file == copied_workflow_config

          src = File.join(context_dir, file)
          if File.exists?(src)
            dst = File.join(rootfs, "app", file)
            Dir.mkdir_p(File.dirname(dst))
            if File.directory?(src)
              copy_dir(src, dst)
            else
              copy_file(src, dst, File.info(src).permissions.value)
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
        files : Array(String) = [] of String,
      ) : String
        final_image = image || "scratch"

        lines = [
          "FROM #{final_image}",
          "COPY rootfs/ /",
          "ENV PATH=\"/usr/bin:/bin:/app/tools:${PATH}\"",
          "ENV SSL_CERT_FILE=\"/etc/ssl/certs/ca-bundle.crt\"",
          "WORKDIR /app",
          "EXPOSE 4111",
          # Use the loader exposed in /usr/lib so the generated image does not
          # depend on the base image's dynamic linker.
          "ENTRYPOINT [\"/usr/lib/ld-linux-x86-64.so.2\", \"--library-path\", \"/usr/lib:/lib\", \"/app/ocawecore\"]",
          "CMD [\"--port\", \"4111\"]",
        ]
        lines.join("\n")
      end

      private def copy_binary_closure(binary : String, rootfs : String) : Nil
        shared_library_closure(binary).each do |library|
          copy_absolute_file(library, rootfs)
          expose_shared_library(library, rootfs)
        end
      end

      private def shared_library_closure(binary : String) : Array(String)
        pending = collect_shared_libraries(binary)
        seen = Set(String).new
        libraries = [] of String
        until pending.empty?
          library = pending.shift
          next if seen.includes?(library)

          seen << library
          libraries << library
          collect_shared_libraries(library).each do |dependency|
            pending << dependency unless seen.includes?(dependency)
          end
        end
        libraries.sort
      end

      private def copy_package_tools(packages : Array(String), rootfs : String) : Nil
        packages.each do |package|
          copy_nix_package(package, rootfs)
        end
      end

      private def copy_default_tools(rootfs : String) : Nil
        ["bash", "sh", "env"].each do |tool|
          if executable = find_executable(tool)
            copy_tool(executable, tool, rootfs)
          end
        end
      end

      private def copy_workflow_cawfile(context_dir : String, rootfs : String) : String?
        ["Cawfile", ".caw"].each do |name|
          cawfile = File.join(context_dir, name)
          next unless File.file?(cawfile)

          copy_file(cawfile, File.join(rootfs, "app", name), File.info(cawfile).permissions.value)
          return name
        end
        nil
      end

      private def copy_tool(executable : String, name : String, rootfs : String) : Nil
        destination = File.join(rootfs, "usr", "bin", name)
        copy_executable(executable, destination)
        collect_shared_libraries(executable).each do |library|
          copy_absolute_file(library, rootfs)
          expose_shared_library(library, rootfs)
        end
      end

      private def expose_shared_library(source : String, rootfs : String) : Nil
        name = File.basename(source)
        destination = File.join(rootfs, "usr", "lib", name)
        Dir.mkdir_p(File.dirname(destination))
        File.delete(destination) if File.exists?(destination) || File.symlink?(destination)
        File.symlink(source, destination)
      end

      private def write_runtime_entrypoint(rootfs : String) : Nil
        loader = Dir.glob(File.join(rootfs, "nix", "store", "*", "lib64", "ld-linux-x86-64.so.2")).sort.first?
        loader ||= Dir.glob(File.join(rootfs, "nix", "store", "*", "lib", "ld-linux-x86-64.so.2")).sort.first?
        raise "Nix dynamic loader was not included in the runtime closure" unless loader

        loader_lib = File.dirname(loader).sub(/\/lib64$/, "/lib")
        script = "#!/bin/sh\nexec #{loader} --library-path /usr/lib:/lib:#{loader_lib} /app/ocawecore \"$@\"\n"
        destination = File.join(rootfs, "app", "ocawe-entrypoint.sh")
        File.write(destination, script)
        File.chmod(destination, 0o755)
      end

      private def copy_nix_package(package : String, rootfs : String) : Nil
        ref = nix_package_ref(package)
        output = IO::Memory.new
        status = Process.run(
          "nix",
          args: ["build", "--no-link", "--print-out-paths", ref],
          output: output,
          error: Process::Redirect::Inherit
        )
        raise "nix package '#{package}' could not be built from #{ref}" unless status.success?

        package_paths = output.to_s.lines.map(&.strip).reject(&.empty?)
        raise "nix package '#{package}' produced no output paths" if package_paths.empty?

        package_paths.each do |path|
          # Package executables retain their Nix interpreter/RPATH and must
          # use the libraries in their own closure.  Publishing those
          # libraries into /usr/lib can overwrite the runtime's glibc with an
          # ABI-incompatible version (for example codex-acp versus ocawecore).
          copy_nix_closure(path, rootfs, expose_libraries: false)
          link_package_bins(path, rootfs)
          expose_ca_bundle(path, rootfs)
        end
      end

      private def nix_package_ref(package : String) : String
        nixpkgs_attr?(package) ? "nixpkgs##{package}" : package
      end

      private def copy_nix_closure(path : String, rootfs : String, expose_libraries : Bool = false) : Nil
        output = IO::Memory.new
        status = Process.run("nix-store", args: ["-qR", path], output: output, error: Process::Redirect::Inherit)
        raise "could not query nix closure for #{path}" unless status.success?

        output.to_s.lines.map(&.strip).reject(&.empty?).sort!.each do |store_path|
          copy_absolute_path(store_path, rootfs)
          expose_store_path_libraries(store_path, rootfs) if expose_libraries
        end
      end

      private def expose_store_path_libraries(store_path : String, rootfs : String) : Nil
        lib_dir = File.join(store_path, "lib")
        return unless Dir.exists?(lib_dir)

        Dir.children(lib_dir).select { |name| name.starts_with?("lib") && name.includes?(".so") }.sort!.each do |name|
          expose_shared_library(File.join(lib_dir, name), rootfs)
        end
      end

      private def link_package_bins(package_path : String, rootfs : String) : Nil
        bin_dir = File.join(package_path, "bin")
        return unless Dir.exists?(bin_dir)

        Dir.children(bin_dir).sort.each do |name|
          src = File.join(bin_dir, name)
          next unless File.exists?(src)

          dst = File.join(rootfs, "usr", "bin", name)
          Dir.mkdir_p(File.dirname(dst))
          File.delete(dst) if File.exists?(dst) || File.symlink?(dst)
          File.symlink(src, dst)
        end
      end

      # Nix packages keep shared objects under their store path. The generated
      # image also contains the closure, but the normal dynamic linker does not
      # search /nix/store. Expose package libraries in the conventional image
      # search path while retaining absolute store-backed symlinks.
      private def link_package_shared_libraries(package_path : String, rootfs : String) : Nil
        lib_dir = File.join(package_path, "lib")
        return unless Dir.exists?(lib_dir)

        # Use Dir.children rather than a glob here. Crystal's glob handling
        # has varied across the runtime versions used by the workflow image,
        # while children preserves both versioned objects and their symlinks.
        libraries = Dir.children(lib_dir).select { |name| name.starts_with?("lib") && name.includes?(".so") }.sort!
        puts "[ocawe] exposing #{libraries.size} shared libraries from #{package_path}" unless libraries.empty?
        libraries.each do |name|
          source = File.join(lib_dir, name)
          name = File.basename(source)
          destination = File.join(rootfs, "usr", "lib", name)
          Dir.mkdir_p(File.dirname(destination))
          File.delete(destination) if File.exists?(destination) || File.symlink?(destination)
          File.symlink(source, destination)
        end
      end

      # Nix's certificate bundle lives under its store path, while HTTP
      # clients in a scratch image conventionally look in /etc/ssl/certs.
      # Expose it without copying secrets or relying on the host filesystem.
      private def expose_ca_bundle(package_path : String, rootfs : String) : Nil
        source = [
          File.join(package_path, "etc", "ssl", "certs", "ca-bundle.crt"),
          File.join(package_path, "etc", "ssl", "certs", "ca-certificates.crt"),
        ].find { |candidate| File.file?(candidate) }
        return unless source

        certificates = File.join(rootfs, "etc", "ssl", "certs")
        Dir.mkdir_p(certificates)
        bundle = File.join(certificates, "ca-bundle.crt")
        copy_file(source, bundle, 0o644)

        legacy = File.join(certificates, "ca-certificates.crt")
        File.delete(legacy) if File.exists?(legacy) || File.symlink?(legacy)
        File.symlink("ca-bundle.crt", legacy)
      end

      private def collect_shared_libraries(binary : String) : Array(String)
        output = IO::Memory.new
        status = Process.run("ldd", args: [binary], output: output, error: Process::Redirect::Close)
        return [] of String unless status.success?

        libraries = Set(String).new
        output.to_s.each_line do |line|
          if match = line.match(/^\s*(\/\S+)/)
            libraries << match[1]
          end
          if match = line.match(/=>\s+(\/\S+)/)
            libraries << match[1]
          end
        end
        libraries.reject { |path| path.includes?("linux-vdso") || !File.file?(path) }.to_a.sort
      end

      private def copy_absolute_file(path : String, rootfs : String) : Nil
        destination = File.join(rootfs, path)
        return if File.exists?(destination)
        Dir.mkdir_p(File.dirname(destination))
        if File.symlink?(path)
          target = File.readlink(path)
          target_path = target.starts_with?("/") ? target : File.expand_path(target, File.dirname(path))
          copy_absolute_file(target_path, rootfs) if File.exists?(target_path)
          File.symlink(target, destination)
          return
        end
        copy_file(path, destination, File.info(path).permissions.value)
      end

      private def copy_absolute_path(path : String, rootfs : String) : Nil
        destination = File.join(rootfs, path)
        if File.directory?(path)
          # A previous binary closure may already have created this store
          # directory with only a subset of its shared libraries.  Merge the
          # package closure into it; skipping an existing directory leaves
          # tools such as codex-acp without libm/libstdc++ at runtime.
          Dir.mkdir_p(destination)
          Dir.children(path).each do |child|
            copy_absolute_path(File.join(path, child), rootfs)
          end
          return
        end

        return if File.exists?(destination)
        Dir.mkdir_p(File.dirname(destination))
        copy_file(path, destination, File.info(path).permissions.value)
      end

      private def find_executable(name : String) : String?
        output = IO::Memory.new
        status = Process.run("sh", args: ["-c", "command -v #{shell_escape(name)}"], output: output, error: Process::Redirect::Close)
        return nil unless status.success?
        path = output.to_s.lines.first?.try(&.strip)
        path.presence
      end

      private def nixpkgs_attr?(package : String) : Bool
        !package.includes?(":") && !package.starts_with?("./") && !package.starts_with?("../") && !package.starts_with?("/")
      end

      private def copy_dir(src : String, dst : String, ignore_context_entries : Bool = true) : Nil
        Dir.mkdir_p(dst)
        Dir.children(src).each do |child|
          next if ignore_context_entries && ignored_context_entry?(child)

          child_src = File.join(src, child)
          child_dst = File.join(dst, child)
          if File.directory?(child_src)
            copy_dir(child_src, child_dst, ignore_context_entries: ignore_context_entries)
          else
            copy_file(child_src, child_dst, File.info(child_src).permissions.value)
          end
        end
      end

      private def ignored_context_entry?(name : String) : Bool
        IGNORED_CONTEXT_ENTRIES.includes?(name)
      end

      private def shell_escape(value : String) : String
        "'" + value.gsub("'", "'\"'\"'") + "'"
      end

      private def copy_executable(src : String, dst : String) : Nil
        copy_file(src, dst, 0o755)
      end

      # Nix's `makeWrapper` exposes commands as shell scripts and keeps the
      # actual ELF beside them as `.name-wrapped`.  A container entrypoint
      # invokes the dynamic loader directly, so copying the wrapper produces
      # an `invalid ELF header` at startup.  Prefer the sibling runtime when
      # it exists; ordinary binaries keep their original path.
      private def unwrap_runtime_binary(binary_path : String) : String
        wrapped = File.join(File.dirname(binary_path), ".#{File.basename(binary_path)}-wrapped")
        return wrapped if File.file?(wrapped) && !File.symlink?(wrapped)
        binary_path
      end

      private def copy_file(src : String, dst : String, mode : Int32) : Nil
        Dir.mkdir_p(File.dirname(dst))
        File.open(src, "r") do |input|
          File.open(dst, "w") do |output|
            IO.copy(input, output)
          end
        end
        File.chmod(dst, mode)
      end
    end
  end
end
