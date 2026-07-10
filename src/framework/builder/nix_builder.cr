require "file_utils"
require "./builder"

module Ocawe
  module Builder
    # Fast workflow image builder. Historical name is kept because Cawfile
    # package-backed containers still resolve to ContainerMode::Nix.
    class NixBuilder < Builder
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

        context = File.join(context_dir, "build", "container")
        FileUtils.rm_rf(context)
        Dir.mkdir_p(context)
        rootfs = File.join(context, "rootfs")
        Dir.mkdir_p(rootfs)

        dockerfile = generate_dockerfile(image: image, packages: packages, files: files)
        File.write(File.join(context, "Dockerfile"), dockerfile)

        copy_executable(binary_path, File.join(rootfs, "app", "ocawecore"))
        copy_binary_closure(binary_path, rootfs)
        copy_package_tools(packages, rootfs)
        copy_default_tools(rootfs)
        copy_workflow_cawfile(context_dir, rootfs)

        effective_files = if files.empty?
                            Dir.children(context_dir).select do |f|
                              path = File.join(context_dir, f)
                              File.exists?(path) && !f.starts_with?('.') && !ignored_context_entry?(f)
                            end
                          else
                            files
                          end

        # Копируем файлы в контекст сборки
        effective_files.each do |file|
          src = File.join(context_dir, file)
          if File.exists?(src)
            dst = File.join(rootfs, "app", file)
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
        files : Array(String) = [] of String,
      ) : String
        final_image = image || "scratch"

        lines = [
          "FROM #{final_image}",
          "COPY rootfs/ /",
          "ENV PATH=\"/usr/bin:/bin:/app/tools:${PATH}\"",
          "WORKDIR /app",
          "EXPOSE 4111",
          "ENTRYPOINT [\"/app/ocawecore\"]",
          "CMD [\"--port\", \"4111\"]",
        ]
        lines.join("\n")
      end

      private def copy_binary_closure(binary : String, rootfs : String) : Nil
        collect_shared_libraries(binary).each do |library|
          copy_absolute_file(library, rootfs)
        end
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

      private def copy_workflow_cawfile(context_dir : String, rootfs : String) : Nil
        cawfile = File.join(context_dir, "Cawfile")
        return unless File.file?(cawfile)
        copy_file(cawfile, File.join(rootfs, "app", "Cawfile"), File.info(cawfile).permissions.value)
      end

      private def copy_tool(executable : String, name : String, rootfs : String) : Nil
        destination = File.join(rootfs, "usr", "bin", name)
        copy_executable(executable, destination)
        collect_shared_libraries(executable).each do |library|
          copy_absolute_file(library, rootfs)
        end
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
          copy_nix_closure(path, rootfs)
          link_package_bins(path, rootfs)
        end
      end

      private def nix_package_ref(package : String) : String
        nixpkgs_attr?(package) ? "nixpkgs##{package}" : package
      end

      private def copy_nix_closure(path : String, rootfs : String) : Nil
        output = IO::Memory.new
        status = Process.run("nix-store", args: ["-qR", path], output: output, error: Process::Redirect::Inherit)
        raise "could not query nix closure for #{path}" unless status.success?

        output.to_s.lines.map(&.strip).reject(&.empty?).sort!.each do |store_path|
          copy_absolute_path(store_path, rootfs)
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

      private def collect_shared_libraries(binary : String) : Array(String)
        output = IO::Memory.new
        status = Process.run("ldd", args: [binary], output: output, error: Process::Redirect::Close)
        return [] of String unless status.success?

        libraries = Set(String).new
        output.to_s.each_line do |line|
          if match = line.match(/=>\s+(\/\S+)/)
            libraries << match[1]
          elsif match = line.match(/^\s*(\/\S+)/)
            libraries << match[1]
          end
        end
        libraries.reject { |path| path.includes?("linux-vdso") || !File.file?(path) }.to_a.sort
      end

      private def copy_absolute_file(path : String, rootfs : String) : Nil
        destination = File.join(rootfs, path)
        return if File.exists?(destination)
        Dir.mkdir_p(File.dirname(destination))
        copy_file(path, destination, File.info(path).permissions.value)
      end

      private def copy_absolute_path(path : String, rootfs : String) : Nil
        destination = File.join(rootfs, path)
        return if File.exists?(destination)
        Dir.mkdir_p(File.dirname(destination))
        if File.directory?(path)
          copy_dir(path, destination, ignore_context_entries: false)
        else
          copy_file(path, destination, File.info(path).permissions.value)
        end
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
        [".git", ".turbo", ".next", "build", "dist", "coverage", "node_modules"].includes?(name)
      end

      private def shell_escape(value : String) : String
        "'" + value.gsub("'", "'\"'\"'") + "'"
      end

      private def copy_executable(src : String, dst : String) : Nil
        copy_file(src, dst, 0o755)
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
