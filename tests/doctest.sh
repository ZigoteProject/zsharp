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
