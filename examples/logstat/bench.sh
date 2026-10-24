#!/usr/bin/env bash
# Builds logstat with --release and measures it on generated logs: binary size, then time
# (best of 3) and peak RSS on 1, 2, 4, 8 and every core.
#   ./dev examples/logstat/bench.sh [lines] [files]      (default 1,000,000 lines in 8 files)
set -eu
cd "$(dirname "$0")/../.."
lines=${1:-1000000} files=${2:-8}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

bin/zs build examples/logstat/src/main.zs -o "$t/logstat" --release
strip -o "$t/stripped" "$t/logstat"
echo "binary: $(stat -c %s "$t/logstat") bytes, $(stat -c %s "$t/stripped") stripped"

# lines/files lines per file, 1 in 100 of them garbage
mkdir "$t/logs"
awk -v n=$((lines / files)) -v files="$files" -v dir="$t/logs" 'BEGIN {
  srand(1)
  split("DEBUG INFO INFO INFO INFO WARN ERROR", lv, " ")
  split("GET GET GET POST DELETE", m, " ")
  split("/ /health /api/users /api/orders /api/reports /api/users/42 /static/app.js", p, " ")
  split("200 200 200 201 304 404 429 500 503", st, " ")
  for (f = 1; f <= files; f++)
    for (i = 0; i < n; i++)
      if (rand() < 0.01) print "garbage line " i > (dir "/" f ".log")
      else printf "2025-12-09T%02d:%02d:%02dZ %s %s %s %s %dms\n", i / 3600 % 24, i / 60 % 60, i % 60,
        lv[int(rand() * 7) + 1], m[int(rand() * 5) + 1], p[int(rand() * 7) + 1], st[int(rand() * 9) + 1],
        int(rand() * rand() * 3000) > (dir "/" f ".log")
}'
echo "input: $lines lines in $files files, $(du -sh "$t/logs" | cut -f1)"

# best of 3: seconds and peak RSS
measure() {
  local best="" rss=0
  for _ in 1 2 3; do
    env "$@" /usr/bin/time -f "%e %M" -o "$t/m" "$t/logstat" "$t/logs" >/dev/null
    read -r s kb <"$t/m"
    if [ -z "$best" ] || awk "BEGIN { exit !($s < $best) }"; then best=$s; fi
    [ "$kb" -gt "$rss" ] && rss=$kb
  done
  printf '%-18s %6ss  %6d MB peak RSS\n' "$1" "$best" $((rss / 1024))
}
for w in 1 2 4 8 "$(nproc)"; do measure ZS_WORKERS="$w"; done
