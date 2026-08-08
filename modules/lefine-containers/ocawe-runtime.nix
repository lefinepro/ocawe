{ pkgs, lib ? pkgs.lib }:

rec {
  storeSource = ../../../ocawe;
  runtimeSource = "/opt/ocawe/source";
  sourceLink = runtimeSource;

  skipIfRunning = containerName: ''
    if nerdctl ps --filter name=${containerName} --format '{{.Status}}' | awk '$0 == "Up" { ok = 1 } END { exit ok ? 0 : 1 }'; then
      echo "Skipping Ocawe bootstrap for ${containerName}; existing container is running"
      exit 0
    fi
  '';

  ensureSource = serviceName: ''
    ocawe_runtime_lock="/run/ocawe-runtime-source.lock"
    while ! mkdir "$ocawe_runtime_lock" >/dev/null 2>&1; do
      sleep 1
    done
    trap 'rmdir "$ocawe_runtime_lock" >/dev/null 2>&1 || true' EXIT

    store_ocawe="${storeSource}"
    runtime_ocawe="${runtimeSource}"
    ocawe_src="${sourceLink}"
    if [ -L "$ocawe_src" ]; then
      linked_ocawe="$(readlink "$ocawe_src")"
      if [ "$linked_ocawe" = "$ocawe_src" ]; then
        rm -f "$ocawe_src"
        ocawe_src="$runtime_ocawe"
      else
        ocawe_src="$linked_ocawe"
      fi
    fi
    if [ ! -f "$ocawe_src/shard.yml" ] || [ ! -d "$ocawe_src/src/cli/endpoints" ] || [ ! -d "$ocawe_src/lib/opentelemetry-sdk" ] || [ ! -x "$ocawe_src/lib/protobuf/bin/protoc-gen-crystal" ] || ! grep -q 'def marketplace_request_activity' "$ocawe_src/src/framework/integration/pipeline_helpers.cr" 2>/dev/null || ! grep -q 'actor_type' "$ocawe_src/src/framework/config/settings.cr" 2>/dev/null; then
      mkdir -p "$(dirname "$runtime_ocawe")"
      rm -rf "$runtime_ocawe.tmp"
      cp -R "$store_ocawe" "$runtime_ocawe.tmp"
      chmod -R u+w "$runtime_ocawe.tmp"
      rm -rf "$runtime_ocawe.tmp/build" "$runtime_ocawe.tmp/.git"
      rm -rf "$runtime_ocawe"
      mv "$runtime_ocawe.tmp" "$runtime_ocawe"
      ocawe_src="$runtime_ocawe"
    fi
    if [ ! -f "$ocawe_src/shard.yml" ] || [ ! -d "$ocawe_src/src/cli/endpoints" ]; then
      echo "Missing ocawe source checkout for ${serviceName}"
      exit 1
    fi
    mkdir -p /opt/ocawe
    if [ "$ocawe_src" != "${sourceLink}" ]; then
      rm -rf ${sourceLink}
      ln -sfn "$ocawe_src" ${sourceLink}
    fi
    rmdir "$ocawe_runtime_lock" >/dev/null 2>&1 || true
    trap - EXIT
  '';

  reuseOrBuildImage =
    {
      image,
      preferOcawe ? false,
      dockerfileAware ? false,
    }:
    ''
      if nerdctl image inspect orator:latest >/dev/null 2>&1; then
        nerdctl tag orator:latest ${image}:latest >/dev/null
      ${lib.optionalString preferOcawe ''
      elif nerdctl image inspect ocawe:latest >/dev/null 2>&1; then
        nerdctl tag ocawe:latest ${image}:latest >/dev/null
      ''}
      else
        ${if dockerfileAware then ''
        if [ -f "$ocawe_src/Containerfile" ]; then
          nerdctl build -t ${image}:latest "$ocawe_src"
        elif [ -f "$ocawe_src/Dockerfile" ]; then
          nerdctl build -t ${image}:latest -f "$ocawe_src/Dockerfile" "$ocawe_src"
        else
          echo "No Containerfile/Dockerfile found in $ocawe_src"
          exit 1
        fi
        '' else ''
        nerdctl build -t ${image}:latest "$ocawe_src"
        ''}
      fi
    '';
}
