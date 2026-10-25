#!/usr/bin/env bash
# Threading.Alt benchmarks: each bench of bench/alt/bench.zs (built --release), next to its Hopac
# twin in bench/alt/hopac on 1 worker and on all of them. Times are the best of 3 runs; the
# checksums must agree; peak memory (RSS) is shown where it should stay flat (timeout, losers).
#   bench/alt/run.sh             a Markdown table
#   ZS=path/to/zs bench/alt/run.sh   with another compiler
# Hopac needs dotnet (net10, offline from ~/.nuget/packages once restored). On macOS with
# Homebrew's llvm 23 and no ThinLTO:
#   PATH=/opt/homebrew/opt/llvm/bin:$PATH ZS_NO_LTO=1 ZS_NO_SERVER=1 ZS=<compiler> bench/alt/run.sh
set -u
cd "$(dirname "$0")/../.."
ZS=${ZS:-bin/zs}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
benches="pingpong-ch pingpong-alt fanin-ch fanin-mailbox choose-2 choose-8 choose-64 sieve ring timeout losers cancel promise yield"
# Z# only: no Hopac twin
zsOnly=" cancel promise yield "
# peak memory shown
rss=" timeout losers "

$ZS build --release bench/alt/bench.zs -o "$t/bench" || exit 1
dotnet build -c Release bench/alt/hopac --artifacts-path "$t/hopac" --nologo -v q >"$t/dotnet.log" 2>&1 ||
  { cat "$t/dotnet.log"; exit 1; }
hopac=$(find "$t/hopac/bin" -name HBench.dll | head -1)

# peak resident memory in MB of the last run (macOS's time -l, Linux's time -f %M)
peak() {
  if [ "$(uname)" = Darwin ]; then awk '/maximum resident set size/ { printf "%.1f", $1 / 1048576 }' "$t/rss"
  else awk '{ printf "%.1f", $1 / 1024 }' "$t/rss"; fi
}
timed() { if [ "$(uname)" = Darwin ]; then /usr/bin/time -l -o "$t/rss" "$@"; else /usr/bin/time -f %M -o "$t/rss" "$@"; fi; }

# best <command…>: "ms rest… peakMB", the run with the lowest ms of 3 (each prints `name ms rest…`)
best() {
  local b="" line="" m=""
  for _ in 1 2 3; do
    local out; out=$(timed timeout 300 "$@" | grep -v WARNING | tail -1)
    local ms; ms=$(echo "$out" | awk '{ print $2 }')
    if [ -n "$ms" ] && { [ -z "$b" ] || [ "$ms" -lt "$b" ]; }; then b=$ms line=$out m=$(peak); fi
  done
  echo "${line#* } $m"
}

fail=0
echo "| bench | Z# ms | Z# allocs/op | Hopac 1 worker ms | Hopac all workers ms | peak RSS MB (Z# / Hopac 1) |"
echo "|---|---:|---:|---:|---:|---:|"
for b in $benches; do
  read -r zms zallocs zsum zmb <<< "$(best "$t/bench" "$b")"
  h1="-" hn="-" mem="" mark=""
  # no time: all 3 runs failed (a crash, a panic, the timeout)
  [ -n "$zms" ] || { mark=" (Z# failed)"; fail=1; }
  if [[ $zsOnly != *" $b "* ]]; then
    read -r h1 h1sum h1mb <<< "$(best dotnet "$hopac" "$b" 1)"
    read -r hn hnsum _ <<< "$(best dotnet "$hopac" "$b")"
    if [ -z "$h1" ] || [ -z "$hn" ]; then mark="$mark (Hopac failed)"; fail=1
    elif [ -n "$zms" ] && { [ "$zsum" != "$h1sum" ] || [ "$zsum" != "$hnsum" ]; }; then
      mark=" (checksums differ: $zsum, $h1sum, $hnsum)"; fail=1
    fi
    [[ $rss == *" $b "* ]] && mem="$zmb / $h1mb"
  fi
  echo "| $b$mark | $zms | $zallocs | $h1 | $hn | $mem |"
done
exit $fail
