#!/usr/bin/env bash
# src/release.sh's archive, on a copy of the checkout's layout with a stand-in stage 0 (it copies
# itself, so each generation is the same bytes): every member is root's (0/0) and written by its
# owner only, whoever made it and under umask 002; and a numbered release of a tree with files git
# doesn't have (added, ignored) is refused. Prints each mode and owner in the archive, once each.
set -u
cd "$(dirname "$0")/.."
t=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/zsharp/src"
cp src/release.sh src/install.sh src/zs.toml "$t/zsharp/src/"
cp -r lib runtime "$t/zsharp/"
mkdir "$t/zsharp/docs" && cp -r docs/guide "$t/zsharp/docs/"  # the guide, installed too
version=$(sed -n 's/^version = "\(.*\)"$/\1/p' src/zs.toml)
printf '#!/bin/sh\nwhile [ $# -gt 1 ]; do [ "$1" = -o ] && out=$2; shift; done\ncp "$0" "$out"\n' >"$t/stage0"
chmod +x "$t/stage0"
cd "$t/zsharp"
umask 002
chmod g+w lib/prelude.zs

echo "--- the archive"
src/release.sh "$t/stage0" test >/dev/null 2>"$t/err" || { echo "release.sh failed:"; cat "$t/err"; }
for a in dist/zs-test-*.tar.gz; do
  # a name where the archive has one, else the number; GNU tar lists owner/group as one field,
  # bsdtar a link count and then each
  tar -tvzf "$a" | awk '{ print $1, (($2 ~ /\//) ? $2 : $3 "/" $4) }' | LC_ALL=C sort -u
done

echo "--- a numbered release, with files git doesn't have"
g() { git -c user.name=zs -c user.email=zs@example.invalid "$@" >/dev/null 2>&1; }
echo '*.ll' >.gitignore
g init -q && g add -A && g commit -q -m tree
touch lib/extra.zs lib/core/stale.ll
src/release.sh "$t/stage0" "$version" 2>&1 | sed "s/$version/<version>/g"
