#!/usr/bin/env bash
# Writes the library reference with zs doc: one Markdown page per file of lib/, named by its
# module (lib/core/Collections/List.zs: Collections.List.md), into docs/reference or the
# directory given. ./test.sh checks that docs/reference is current.
set -eu
cd "$(dirname "$0")/.."
out=${1:-docs/reference}
mkdir -p "$out"
for f in $(find lib -name '*.zs' | sort); do
  n=${f#lib/}; n=${n#core/}; n=${n#std/}; n=${n%.zs}
  bin/zs doc "$f" > "$out/${n//\//.}.md"
done
