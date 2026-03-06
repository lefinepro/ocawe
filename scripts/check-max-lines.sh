#!/usr/bin/env bash
set -euo pipefail

max_lines="${MAX_FILE_LINES:-300}"
code_ext_regex='\.(cr|sh|rb|py|js|mjs|cjs|ts|tsx|jsx|svelte|yml|yaml)$'
exclude_regex='(^$)'
if [[ -n "${MAX_FILE_LINES_EXCLUDE_REGEX:-}" ]]; then
  exclude_regex="${MAX_FILE_LINES_EXCLUDE_REGEX}"
fi

violations=0

while IFS= read -r -d '' file; do
  if [[ ! -f "$file" ]]; then
    continue
  fi
  if [[ ! "$file" =~ $code_ext_regex ]]; then
    continue
  fi
  if [[ "$file" =~ $exclude_regex ]]; then
    continue
  fi

  line_count=$(wc -l < "$file")
  if (( line_count > max_lines )); then
    printf '%s\t%s\n' "$line_count" "$file"
    violations=1
  fi
done < <(git ls-files -z)

if (( violations > 0 )); then
  echo ""
  echo "Error: some code files exceed ${max_lines} lines."
  exit 1
fi

echo "OK: all tracked code files are within ${max_lines} lines."
