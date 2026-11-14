#!/usr/bin/env bash
# Contained jobs measured (proposal 0035's Pragmatics): bench/contained/jobs.zs, and
# bench/contained/shared.zs built without a contained job and with one, which is what makes a
# program count its shared objects through the runtime.
# Usage, in ./dev: bench/contained/run.sh [jobs] [rounds]
set -eu
cd "$(dirname "$0")/../.."
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
bin/zs build bench/contained/jobs.zs -o "$dir/jobs" --release
"$dir/jobs" "${1:-1000000}" 2>/dev/null
sed 's|^  //CONTAINED |  |' bench/contained/shared.zs > "$dir/with.zs"
bin/zs build bench/contained/shared.zs -o "$dir/without" --release
bin/zs build "$dir/with.zs" -o "$dir/with" --release
for k in 1 2 3; do
  echo "without a contained job:"; "$dir/without" "${2:-200}"
  echo "with one:"; "$dir/with" "${2:-200}"
done
