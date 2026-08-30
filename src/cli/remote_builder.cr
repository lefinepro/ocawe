require "digest/sha256"
require "file_utils"

require "../framework/discovery/cawfile_loader"

module OcaweCore
  module CLI
    # Builds one workflow project on a remote host. The source bundle is kept
    # deliberately small and content-addressed so repeated builds can reuse
    # the remote build directory and container-manager cache.
    class RemoteBuilder
      record Options,
        host : String,
        manager : String = "auto",
        base_image : String = "ocawe:latest",
        runtime_root : String = "/var/lib/ocawe/runtimes",
        deploy : Bool = false,
        namespace : String = "default",
        dry_run : Bool = false

      def initialize(@project_root : String)
      end

      def build(service : String, options : Options) : Bool
        workflow_root = resolve_service(service)
        safe_service = sanitize(service)

        # Do not use a shared `/tmp/context`: another build (or a previous
        # sandbox invocation) may own it or leave it read-only.  A private
        # staging root also makes concurrent service builds safe.
        tmp = File.join(Dir.tempdir, "ocawe-remote-#{Process.pid}-#{Time.utc.to_unix_ms}")
        FileUtils.mkdir_p(tmp)
        begin
          staging = File.join(tmp, "context")
          stage_source(staging, workflow_root)
          generate_entrypoint(staging)
          write_dockerfile(staging, safe_service)

          archive = File.join(tmp, "#{safe_service}.tar.gz")
          run!("tar", ["-C", staging, "--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "-czf", archive, "."])
          hash = Digest::SHA256.hexdigest("#{options.base_image}\n#{File.read(archive)}")
          image = "ocawe/#{safe_service}:#{hash}"
          remote_archive = "/tmp/ocawe-#{safe_service}-#{hash}.tar.gz"

          puts "[ocawe] remote service=#{safe_service} host=#{options.host} hash=#{hash}"
          puts "[ocawe] remote image=#{image}"
          if options.dry_run
            puts "[ocawe] dry-run: would upload #{archive} to #{options.host}:#{remote_archive}"
            return true
          end

          run!("scp", ["-F", "/dev/null", "-o", "StrictHostKeyChecking=no", archive, "#{options.host}:#{remote_archive}"])
          run_remote(options, safe_service, hash, image, remote_archive)
        ensure
          FileUtils.rm_rf(tmp)
        end
        true
      rescue ex
        STDERR.puts "[ocawe] remote build failed: #{ex.message || ex.class.name}"
        false
      end

      private def resolve_service(service : String) : String
        candidates = [
          File.expand_path(File.join("pipelines", service), Dir.current),
          File.expand_path(service, Dir.current),
          File.expand_path(File.join("pipelines", service), @project_root),
          File.expand_path(service, @project_root),
        ]
        path = candidates.find do |candidate|
          File.file?(File.join(candidate, "Cawfile")) && Dir.exists?(candidate)
        end
        return path if path
        raise "service '#{service}' not found; expected pipelines/#{service}/Cawfile or #{service}/Cawfile"
      end

      private def stage_source(staging : String, workflow_root : String) : Nil
        source_root = File.join(staging, "ocawe")
        workflow_target = File.join(staging, "workflow")
        FileUtils.mkdir_p(source_root)
        FileUtils.mkdir_p(workflow_target)

        ["src", "lib"].each do |directory|
          source = File.join(@project_root, directory)
          raise "Ocawe source directory missing: #{source}" unless Dir.exists?(source)
          copy_tree(source, File.join(source_root, directory))
        end
        ["shard.yml", "shard.lock", "shards.nix", "flake.nix", "flake.lock", "README.org"].each do |name|
          source = File.join(@project_root, name)
          raise "Ocawe source file missing: #{source}" unless File.file?(source)
          FileUtils.cp(source, File.join(source_root, name))
        end

        ["caws", "scripts"].each do |directory|
          source = File.join(@project_root, directory)
          raise "Ocawe runtime directory missing: #{source}" unless Dir.exists?(source)
          copy_tree(source, File.join(source_root, directory))
        end

        copy_tree(workflow_root, workflow_target)
        strip_ocawe_requires(workflow_target)
        FileUtils.mkdir_p(File.join(workflow_target, "plugins"))
      end

      # Remote runtimes inject the Ocawe source tree as their first require.
      # Workflow files may still contain the normal shard-style require from
      # local development; remove it from every copied Crystal source file so
      # registry/plugin files compile in the self-contained remote bundle.
      private def strip_ocawe_requires(workflow_root : String) : Nil
        Dir.glob(File.join(workflow_root, "**", "*.cr")).each do |path|
          lines = File.read_lines(path)
          filtered = lines.reject { |line| line.strip == %(require "ocawe") }
          File.write(path, filtered.join("\n") + (filtered.empty? || filtered.last.empty? ? "" : "\n")) if filtered != lines
        end
      end

      private def copy_tree(source : String, target : String) : Nil
        FileUtils.mkdir_p(target)
        Dir.children(source).each do |name|
          next if {".git", ".ocawe", ".env", "build", "node_modules", ".pnpm-store", "dist", "target", "coverage"}.includes?(name)
          next if name.starts_with?(".env.") || name.ends_with?(".pem")
          source_path = File.join(source, name)
          target_path = File.join(target, name)
          next if File.symlink?(source_path)
          if Dir.exists?(source_path)
            copy_tree(source_path, target_path)
          else
            FileUtils.cp(source_path, target_path)
          end
        end
      end

      private def generate_entrypoint(staging : String) : Nil
        source_root = File.join(staging, "ocawe")
        workflow_root = File.join(staging, "workflow")
        bundle = ACD::Discovery::CawfileLoader.load(workflow_root, "root")
        raise "#{workflow_root}/Cawfile could not be loaded" unless bundle
        loader = bundle.not_nil!.crystal_loader
        raise "#{workflow_root}/Cawfile has no Crystal runtime code" unless loader

        output_dir = File.join(workflow_root, "build")
        output = File.join(output_dir, "runtime_entry.cr")
        FileUtils.mkdir_p(output_dir)
        Dir.cd(workflow_root) do
          lines = [] of String
          lines << %(require "#{require_path(output_dir, File.join(source_root, "src", "ocawe"))}")
          loader.not_nil!.code.each do |line|
            lines << runtime_entry_line(line, output_dir)
          end
          loader.not_nil!.registry_files.each do |path|
            require_line = %(require "#{require_path(output_dir, path)}")
            lines << require_line unless lines.includes?(require_line)
          end
          # A workflow may require a plugin directly from its Cawfile while
          # other plugins are only reached through a registry file. Include
          # the complete local plugin tree in the remote runtime so the
          # generated binary cannot silently fall back to an older plugin
          # bundle left in the base image.
          Dir.glob(File.join(workflow_root, "plugins", "**", "*.cr")).sort.each do |path|
            next if File.basename(path) == "registry.cr"
            require_line = %(require "#{require_path(output_dir, path)}")
            lines << require_line unless lines.includes?(require_line)
          end
          lines << ""
          lines << "OcaweCore.run"
          File.write(output, lines.join("\n"))
        end
      end

      private def write_dockerfile(staging : String, service : String) : Nil
        runtime_name = "#{service}-runtime"
        dockerfile = <<-DOCKERFILE
        ARG BASE_IMAGE=ocawe:latest
        FROM nixos/nix:2.28.3 AS build
        WORKDIR /src/ocawe
        COPY ocawe/ /src/ocawe/
        COPY workflow/ /src/workflow/
        # Crystal's default parallelism can exhaust the small production
        # builder while compiling the embedded Ocawe runtime. Keep remote
        # builds deterministic and within the host memory budget.
        RUN cd /src/ocawe \\
          && mkdir -p /out \\
          && nix develop . --command crystal build /src/workflow/build/runtime_entry.cr --threads 1 --release --no-debug -o /out/#{runtime_name}

        FROM ${BASE_IMAGE}
        WORKDIR /workflows/#{service}
        COPY --from=build /out/#{runtime_name} /runtime/#{runtime_name}
        COPY workflow/Cawfile /workflows/#{service}/Cawfile
        COPY workflow/plugins /workflows/#{service}/plugins
        ENTRYPOINT ["/runtime/#{runtime_name}", "-p", "8080"]
        DOCKERFILE
        File.write(File.join(staging, "Dockerfile"), dockerfile)
      end

      private def run_remote(options : Options, service : String, hash : String, image : String, remote_archive : String) : Nil
        script = remote_script
        args = ["-F", "/dev/null", "-o", "StrictHostKeyChecking=no", options.host, "bash", "-s", "--", service, hash, image, remote_archive, options.manager, options.base_image, options.runtime_root, options.deploy ? "1" : "0", options.namespace]
        status = Process.run("ssh", args: args, input: IO::Memory.new(script), output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        raise "remote build command exited with status #{status.exit_code}" unless status.success?
      end

      private def remote_script : String
        <<-SCRIPT
        set -euo pipefail
        service="$1"
        hash="$2"
        image="$3"
        archive="$4"
        requested_manager="$5"
        base_image="$6"
        runtime_root="$7"
        deploy="$8"
        namespace="$9"
        runtime_name="${service}-runtime"
        service_root="${runtime_root}/${service}"
        build_root="/tmp/ocawe-builds/${service}/${hash}"
        version_root="${service_root}/${hash}"
        store_metadata="${service_root}/current.json"

        if [ "$(id -u)" -eq 0 ]; then
          sudo_cmd=()
        else
          sudo_cmd=(sudo)
        fi
        run_privileged() { "${sudo_cmd[@]}" "$@"; }

        manager="$requested_manager"
        manager_sudo=0
        if [ "$manager" = auto ]; then
          for candidate in nerdctl docker podman; do
            if command -v "$candidate" >/dev/null 2>&1 && "$candidate" info >/dev/null 2>&1; then
              manager="$candidate"
              break
            elif command -v sudo >/dev/null 2>&1 && sudo -n "$candidate" info >/dev/null 2>&1; then
              manager="$candidate"
              manager_sudo=1
              break
            fi
          done
        fi
        case "$manager" in
          nerdctl)
            manager_cmd=(nerdctl)
            ;;
          docker|podman)
            manager_cmd=("$manager")
            ;;
          *)
            echo "[ocawe] no usable remote container manager (nerdctl, docker, podman)" >&2
            exit 1
            ;;
        esac

        if [ "$manager_sudo" = "0" ] && ! "${manager_cmd[@]}" info >/dev/null 2>&1; then
          if command -v sudo >/dev/null 2>&1 && sudo -n "${manager_cmd[@]}" info >/dev/null 2>&1; then
            manager_sudo=1
          fi
        fi
        run_manager() {
          if [ "$manager_sudo" = "1" ]; then
            sudo -n "${manager_cmd[@]}" "$@"
          else
            "${manager_cmd[@]}" "$@"
          fi
        }
        run_privileged mkdir -p "$build_root"
        run_privileged mkdir -p "$service_root"
        image_archive="$build_root/${service}-${hash}.tar"
        # A failed image import can leave the runtime binary behind before the
        # version metadata is committed.  Only that version-local metadata
        # marks a complete cache entry; the service-level metadata may belong
        # to an older successful build.
        if [ -x "$version_root/$runtime_name" ] && [ -f "$version_root/metadata.json" ]; then
          echo "[ocawe] remote cache hit: $service $hash"
        else
          if [ -x "$version_root/$runtime_name" ] && [ -f "$image_archive" ]; then
            echo "[ocawe] resuming image import: $service $hash"
            run_privileged rm -f "$archive"
          else
            run_privileged rm -rf "$build_root/context"
            run_privileged mkdir -p "$build_root/context"
            run_privileged tar -xzf "$archive" -C "$build_root/context"
            run_privileged rm -f "$archive"
            # The runtime binary is compiled from the staged Ocawe sources. Do
            # not reuse an older Docker build layer here: a remote deployment
            # must contain the exact framework source used for this bundle.
            run_manager build --no-cache --build-arg "BASE_IMAGE=$base_image" -t "$image" "$build_root/context"

            container="ocawe-extract-${service}-${hash}"
            run_manager rm -f "$container" >/dev/null 2>&1 || true
            container_id_file="$build_root/container-id"
            run_privileged rm -f "$container_id_file"
            run_manager create --name "$container" "$image" | run_privileged tee "$container_id_file" >/dev/null
            container_id="$(run_privileged cat "$container_id_file")"
            trap 'run_manager rm -f "$container_id" >/dev/null 2>&1 || true' EXIT
            run_privileged mkdir -p "$build_root/output"
            run_manager cp "$container_id:/runtime/$runtime_name" "$build_root/output/$runtime_name"
            run_manager rm -f "$container_id" >/dev/null 2>&1 || true
            trap - EXIT

            run_privileged mkdir -p "$version_root"
            run_privileged install -m 0755 "$build_root/output/$runtime_name" "$version_root/$runtime_name"
            run_manager save -o "$image_archive" "$image"
          fi
          if command -v k3s >/dev/null 2>&1; then
            run_privileged k3s ctr -n k8s.io images import "$image_archive"
          elif command -v ctr >/dev/null 2>&1; then
            run_privileged ctr -n k8s.io images import "$image_archive"
          else
            echo "[ocawe] cannot import $image into K3s containerd" >&2
            exit 1
          fi

          metadata=$(printf '{"service":"%s","hash":"%s","image":"%s","runtime":"%s","built_at":"%s"}\n' \
            "$service" "$hash" "$image" "$runtime_name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
          printf '%s\n' "$metadata" | run_privileged tee "$version_root/metadata.json" >/dev/null
        fi

        run_privileged ln -sfn "$hash" "$service_root/current.next"
        run_privileged mv -Tf "$service_root/current.next" "$service_root/current"
        run_privileged ln -sfn "$service/$hash/$runtime_name" "$runtime_root/$runtime_name.next"
        run_privileged mv -Tf "$runtime_root/$runtime_name.next" "$runtime_root/$runtime_name"
        run_privileged cp "$version_root/metadata.json" "$store_metadata.next"
        run_privileged mv -Tf "$store_metadata.next" "$store_metadata"
        echo "[ocawe] promoted $service $hash ($image)"
        if [ "$deploy" = "1" ]; then
          command -v kubectl >/dev/null 2>&1 || { echo "[ocawe] --deploy requires kubectl on the remote host" >&2; exit 1; }
          kubectl_args=(--kubeconfig /etc/rancher/k3s/k3s.yaml -n "$namespace")
          if [ "$(id -u)" -eq 0 ]; then
            kubectl_cmd=(kubectl)
          else
            kubectl_cmd=(sudo -n kubectl)
          fi
          if [ -f "$build_root/context/workflow/Cawfile" ]; then
            "${kubectl_cmd[@]}" "${kubectl_args[@]}" create configmap "${service}-workflow" \
              --from-file="Cawfile=$build_root/context/workflow/Cawfile" \
              --dry-run=client -o yaml | "${kubectl_cmd[@]}" "${kubectl_args[@]}" apply -f -
          fi
          if [ -d "$build_root/context/workflow/plugins" ]; then
            plugin_args=()
            while IFS= read -r -d '' plugin_file; do
              plugin_name="$(basename "$plugin_file")"
              plugin_args+=("--from-file=${plugin_name}=${plugin_file}")
            done < <(find "$build_root/context/workflow/plugins" -type f -print0 | sort -z)
            if [ "${#plugin_args[@]}" -gt 0 ]; then
              "${kubectl_cmd[@]}" "${kubectl_args[@]}" create configmap "${service}-plugins" \
                "${plugin_args[@]}" \
              --dry-run=client -o yaml | "${kubectl_cmd[@]}" "${kubectl_args[@]}" apply -f -
            fi
          fi
          # Strategic merge keeps project-owned environment variables and data
          # mounts. Only the legacy host-mounted runtime is removed so the
          # binary from this exact image remains authoritative.
          patch_payload=$(printf '{"spec":{"template":{"spec":{"containers":[{"name":"%s","image":"%s","volumeMounts":[{"mountPath":"/workflows/%s/Cawfile","name":"cawfile","subPath":"Cawfile"},{"mountPath":"/workflows/%s/plugins","name":"plugins"},{"mountPath":"/runtime","$patch":"delete"},{"mountPath":"/runtime/%s","$patch":"delete"}]}]}}}}' "$service" "$image" "$service" "$service" "$runtime_name")
          "${kubectl_cmd[@]}" "${kubectl_args[@]}" patch deployment "$service" --type=strategic -p "$patch_payload"
          "${kubectl_cmd[@]}" "${kubectl_args[@]}" set image "deployment/$service" "$service=$image"
          "${kubectl_cmd[@]}" "${kubectl_args[@]}" rollout status "deployment/$service" --timeout=180s
          echo "[ocawe] deployed $service to namespace $namespace"
        fi
        SCRIPT
      end

      private def runtime_entry_line(line : String, entrypoint_dir : String) : String
        stripped = line.strip
        # The generated entrypoint already requires the Ocawe source tree.
        # Keeping a Cawfile's shard-style `require "ocawe"` makes Crystal
        # search only the workflow shard path on the remote build and fails.
        return "" if stripped == %(require "ocawe")
        if match = stripped.match(/^require\s+"([^"]+)"/)
          required = match[1]
          if required.starts_with?(".")
            target = File.expand_path(required, Dir.current)
            return %(require "#{require_path(entrypoint_dir, target)}")
          end
        end
        line
      end

      private def require_path(from_dir : String, target : String) : String
        relative = Path[File.expand_path(target)].relative_to(Path[File.expand_path(from_dir)]).to_s
        relative = "./#{relative}" unless relative.starts_with?(".")
        relative.sub(/\.cr$/, "")
      end

      private def sanitize(value : String) : String
        value.gsub(/[^a-zA-Z0-9_.-]/, "-")
      end

      private def run!(program : String, args : Array(String)) : Nil
        status = Process.run(program, args: args, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        raise "command failed: #{program} #{args.join(" ")}" unless status.success?
      end
    end
  end
end
