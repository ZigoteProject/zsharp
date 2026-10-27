#!/usr/bin/env bash
# zs test --doc (0009, D8): tests/doctest/area.zs's blocks, one passing and one expecting the wrong
# thing, then --update rewriting that one to what it printed, then both passing
zs=$(realpath "${1:-bin/zs}"); dir=$(mktemp -d)
cp tests/doctest/area.zs "$dir/area.zs"
(cd "$dir" && "$zs" test --doc area.zs)
(cd "$dir" && "$zs" test --doc --update area.zs >/dev/null)
diff "$dir/area.zs" tests/doctest/area.updated && echo "updated as expected"
(cd "$dir" && "$zs" test --doc area.zs | tail -1)
rm -rf "$dir"
# a library file's blocks are built in this user's cache, not the shared temporary directory,
# where another user could put .zs-doctest.zs first and change it before it's built and run
tmp=$(mktemp -d)
ZS_NO_SERVER=1 TMPDIR=$tmp "$zs" test --doc lib/core/Text/Utf8.zs | tail -1
echo "left in TMPDIR: $(ls -A "$tmp" | wc -l)"; ls -A "$tmp" >&2
rm -rf "$tmp"
