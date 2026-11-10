#!/usr/bin/env bash
# examples/tools (track S's exit test): grep, a JSON pretty-printer and tail -f, each under 100
# lines, built and run on small inputs; tail -f followed while lines are appended, then stopped.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# $t as the tools print it: on Windows, Git Bash hands a native program /tmp/… as C:/…/Temp/…
at=$t; command -v cygpath >/dev/null && at=$(cygpath -m "$t")
for e in grep jsonpp tail; do
  "$zs" build examples/tools/$e.zs -o "$t/$e" || exit 1
  echo "$e: $(wc -l < examples/tools/$e.zs | tr -d ' ') lines" # (tr: BSD's wc, macOS's, pads its count)
done
printf 'Apple pie\nbanana split\ncherry tart\napple crumble\n' > "$t/a.txt"
printf 'no fruit here\nAPPLE sauce\n' > "$t/b.txt"
echo "== grep"
"$t/grep" apple "$t/a.txt"; echo "exit $?"
"$t/grep" -i -n apple "$t/a.txt" "$t/b.txt" | sed "s|$at/||"; echo "exit $?"
"$t/grep" -v a "$t/a.txt"; echo "exit $?"
printf 'x\ny\n' | "$t/grep" z; echo "exit $?"
"$t/grep" apple "$t/missing.txt" 2>&1 | sed "s|$at/||g"; echo "exit ${PIPESTATUS[0]}"
"$t/grep"; echo "exit $?"
echo "== jsonpp"
printf '{"name":"Z#","tags":["ml","native"],"stars":{"host":true,"chip":true},"none":null}' > "$t/d.json"
"$t/jsonpp" "$t/d.json"; echo
"$t/jsonpp" --compact "$t/d.json"
echo '[1, 2' | "$t/jsonpp"; echo "exit $?"
echo "== tail"
seq 1 12 > "$t/log"
"$t/tail" -n 3 "$t/log"
"$t/tail" "$t/log" | head -1
# followed: a line appended, two more, the file rewritten, then removed, which ends the follow
( sleep 0.6; echo 13 >> "$t/log"; sleep 0.6; printf '14\n15\n' >> "$t/log"; sleep 0.6; printf 'new\n' > "$t/log"; sleep 0.6; rm "$t/log" ) &
timeout 10 "$t/tail" -n 2 -f "$t/log" 2>&1 | sed "s|$at/||g"; echo "exit ${PIPESTATUS[0]}"
wait
seq 1 3 > "$t/log"
"$t/tail" -n x "$t/log"; echo "exit $?"
