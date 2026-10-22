#!/usr/bin/env bash
# Regenerates the grammar and shows, for each .zs file that doesn't parse cleanly, the source
# lines of its first ERROR/MISSING nodes. Each parse is limited to 10 s and 4 GB.
cd "$(dirname "$0")/../../.."
ulimit -v 4000000
(cd editors/tree-sitter-zsharp && timeout 300 tree-sitter generate >/dev/null) || { echo "generate failed"; exit 1; }
total=0
# (tests/newcomer: the mistakes newcomers make, some in another language's syntax on purpose)
for f in ${@:-$(find tests lib examples -name '*.zs' -not -path 'tests/newcomer/*' | sort)}; do
  out=$(timeout 10 tree-sitter parse --grammar-path editors/tree-sitter-zsharp "$f" 2>/dev/null)
  [ $? = 124 ] && { echo "TIMEOUT $f"; continue; }
  lines=$(printf '%s\n' "$out" | grep -o '(\(ERROR\|MISSING[^[]*\) \[[0-9]*' | grep -o '[0-9]*$' | sort -un | head -${N:-3})
  [ -z "$lines" ] && continue
  total=$((total + 1))
  for l in $lines; do printf '%s:%d: %s\n' "$f" $((l + 1)) "$(sed -n "$((l + 1))p" "$f")"; done
done
echo "files with errors: $total"
