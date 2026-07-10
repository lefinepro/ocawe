module Ocawe
  module Builder
    abstract class Builder
      getter base : String

      def initialize(@base : String)
      end

      abstract def build(
        binary_path : String,
        tag : String = "",
        context_dir : String = ".",
        runtime : String = "docker",
        image : String? = nil,
        packages : Array(String) = [] of String,
        files : Array(String) = [] of String,
      ) : Bool

      protected def run_build_command(runtime : String, context : String, tag : String) : Bool
        unless runtime_available?(runtime)
          return build_rootfs_archive(context, tag)
        end

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

      private def runtime_available?(runtime : String) : Bool
        Process.run("sh", args: ["-c", "command -v #{shell_escape(runtime)} >/dev/null 2>&1"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
      end

      private def build_rootfs_archive(context : String, tag : String) : Bool
        rootfs = File.join(context, "rootfs")
        unless Dir.exists?(rootfs)
          STDERR.puts "[ocawe] build failed: container runtime unavailable and no rootfs prepared"
          return false
        end

        archive = File.join(context, "#{archive_name(tag)}.rootfs.tar")
        status = if packer = rootfs_packer
                   if workflow_dir = workflow_dir_for_container_context(context)
                     Process.run(packer, args: ["--build", workflow_dir, tag], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
                   else
                     Process.run(packer, args: [rootfs, archive], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
                   end
                 else
                   Process.run("tar", args: ["-C", rootfs, "-cf", archive, "."], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
                 end
        if status.success?
          puts "[ocawe] container runtime unavailable; built rootfs archive: #{archive}"
        else
          STDERR.puts "[ocawe] rootfs archive build failed: #{archive}"
        end
        status.success?
      end

      private def archive_name(tag : String) : String
        tag.gsub(/[^a-zA-Z0-9_.-]/, "-")
      end

      private def workflow_dir_for_container_context(context : String) : String?
        expanded = File.expand_path(context)
        return nil unless File.basename(expanded) == "container"
        build_dir = File.dirname(expanded)
        return nil unless File.basename(build_dir) == "build"
        workflow_dir = File.dirname(build_dir)
        File.file?(File.join(workflow_dir, "Cawfile")) ? workflow_dir : nil
      end

      private def shell_escape(value : String) : String
        "'" + value.gsub("'", "'\"'\"'") + "'"
      end

      private def rootfs_packer : String?
        candidates = [] of String
        if env = ENV["OCAWE_ROOTFS_TAR"]?
          candidates << env
        end
        if executable = Process.executable_path
          candidates << File.join(File.dirname(executable), "rootfs_tar")
        end
        candidates << File.expand_path("build/rootfs_tar", Dir.current)
        candidates.find { |path| executable_file?(path) }
      end

      private def executable_file?(path : String) : Bool
        info = File.info(path)
        File.file?(path) && (info.permissions.value & 0o111) != 0
      rescue
        false
      end

      protected def copy_binary(src : String, dst : String) : Nil
        File.open(src, "r") do |input|
          File.open(dst, "w") do |output|
            IO.copy(input, output)
          end
        end
        File.chmod(dst, 0o755)
      end
    end
  end
end
