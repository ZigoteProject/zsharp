#!/usr/bin/env bash
# A release of the compiler for this machine's Linux: src/ built --release by the given
# compiler, then by that build, then by that one: the last two must be the same bytes (the
# compiler builds itself to itself), and it's what's released, installed with its library and
# runtime, and archived:
#   src/release.sh <zs> <version>   ->   dist/zs-<version>-linux-<arch>.tar.gz
set -eu
cd "$(dirname "$0")/.."
stage=$1; version=$2
arch=$(uname -m)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# the library and the runtime of the tree: a build in a directory of its own has neither
export ZS_NO_SERVER=1 ZS_LIB=$PWD/lib ZS_RUNTIME=$PWD/runtime
XDG_CACHE_HOME=$t/cache1 "$stage" build src/Main.zs --release -o "$t/zs1"
XDG_CACHE_HOME=$t/cache2 "$t/zs1" build src/Main.zs --release -o "$t/zs2"
XDG_CACHE_HOME=$t/cache3 "$t/zs2" build src/Main.zs --release -o "$t/zs3"
cmp -s "$t/zs2" "$t/zs3" || { echo "the compiler doesn't build itself to the same binary" >&2; exit 1; }
name=zs-$version-linux-$arch
src/install.sh "$t/zs3" "$t/$name"
mkdir -p dist
tar -czf "dist/$name.tar.gz" -C "$t" "$name"
echo "dist/$name.tar.gz"
