#!/usr/bin/env bash
set -euo pipefail

# Convert markdown files to org format in the caws/ directory
# Usage: ./scripts/convert-to-org.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/convert-to-org.py" "$PROJECT_DIR/caws"

echo "Conversion complete!"
