#!/usr/bin/env bash
set -euo pipefail

nix develop --command crystal build src/ocawe.cr --no-codegen
