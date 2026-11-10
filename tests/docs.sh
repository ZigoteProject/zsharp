#!/usr/bin/env bash
# Checks the examples in docs/guide: every ```zsharp block is a whole program that must build
# (a block without `main` gets `let main () = 0`), and a ```text block right after it is the
# program's exact output; a ```text windows block right after that is its output on Windows, where
# it differs by design (a path Path joined with Windows' \). Prints one line per failing example,
# then a count.
zs=${1:-bin/zs}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export ZS_BACKTRACE=0
windows=0; case $(uname -s) in MINGW* | MSYS* | CYGWIN*) windows=1 ;; esac
fails=0; total=0
for md in docs/guide/*.md; do
  # split into numbered example files: N.zs (code), N.out (expected output, if any) and
  # N.windows.out (Windows' expected output, if it differs)
  awk -v dir="$tmp" -v base="$(basename "$md" .md)" '
    /^```zsharp/ { n++; file = dir "/" base "-" n ".zs"; mode = "code"; next }
    /^```text windows/ && last == "out" { file = dir "/" base "-" n ".windows.out"; mode = "windows"; next }
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
  out=${z%.zs}.out; [ $windows = 1 ] && [ -f "${z%.zs}.windows.out" ] && out=${z%.zs}.windows.out
  if [ -f "$out" ] && [ "$actual" != "$(cat "$out")" ]; then
    echo "FAIL docs/guide/${name%-*}.md example ${name##*-}: output differs"
    diff <(cat "$out") <(echo "$actual") | head -10 | sed 's/^/    /'; fails=$((fails + 1))
  fi
done
echo "$((total - fails)) of $total examples ok"
[ $fails = 0 ]
