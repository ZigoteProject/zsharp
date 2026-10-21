#!/usr/bin/env bash
# Checks the examples in docs/guide: every ```zsharp block is a whole program that must build
# (a block without `main` gets `let main () = 0`), and a ```text block right after it is the
# program's exact output. Prints one line per failing example, then a count.
zs=${1:-bin/zs}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export ZS_BACKTRACE=0
fails=0; total=0
for md in docs/guide/*.md; do
  # split into numbered example files: N.zs (code) and N.out (expected output, if any)
  awk -v dir="$tmp" -v base="$(basename "$md" .md)" '
    /^```zsharp/ { n++; file = dir "/" base "-" n ".zs"; mode = "code"; next }
    /^```text/ && last == "code" { file = dir "/" base "-" n ".out"; mode = "out"; next }
    /^```/ { if (mode != "") { last = mode; mode = "" } else last = ""; next }
    mode != "" { print > file; next }
    NF { last = "" }
  ' "$md"
done
for z in "$tmp"/*.zs; do
  [ -e "$z" ] || continue
  total=$((total + 1)); name=$(basename "$z" .zs)
  grep -q "^let main" "$z" || printf '\nlet main () = 0\n' >> "$z"
  if ! timeout 60 "$zs" build "$z" -o "$tmp/exe" >"$tmp/log" 2>&1; then
    echo "FAIL docs/guide/${name%-*}.md example ${name##*-}: does not build"; sed 's/^/    /' "$tmp/log" | head -8; fails=$((fails + 1)); continue
  fi
  actual=$(cd "$tmp" && timeout 10 ./exe 2>&1 </dev/null)
  if [ -f "${z%.zs}.out" ] && [ "$actual" != "$(cat "${z%.zs}.out")" ]; then
    echo "FAIL docs/guide/${name%-*}.md example ${name##*-}: output differs"
    diff <(cat "${z%.zs}.out") <(echo "$actual") | head -10 | sed 's/^/    /'; fails=$((fails + 1))
  fi
done
echo "$((total - fails)) of $total examples ok"
[ $fails = 0 ]
