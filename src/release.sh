#!/usr/bin/env bash
# A release of the compiler for this machine's Linux: src/ built --release by the given
# compiler, then by that build, then by that one: the last two must be the same bytes (the
# compiler builds itself to itself), and it's what's released, installed with its library and
# runtime, and archived. Each target named after the version is a release for that platform too,
# src/ built for it (--target) by that compiler:
#   src/release.sh <zs> <version> [<target>...]   ->   dist/zs-<version>-<os>-<arch>.tar.gz
#   (targets: aarch64-macos, x86_64-macos, x86_64-windows-gnu, aarch64-windows-gnu, aarch64-linux-gnu)
set -eu
cd "$(dirname "$0")/.."
stage=$1; version=$2; shift 2
arch=$(uname -m)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# the library and the runtime of the tree: a build in a directory of its own has neither
export ZS_NO_SERVER=1 ZS_LIB=$PWD/lib ZS_RUNTIME=$PWD/runtime
XDG_CACHE_HOME=$t/cache1 "$stage" build src/Main.zs --release -o "$t/zs1"
XDG_CACHE_HOME=$t/cache2 "$t/zs1" build src/Main.zs --release -o "$t/zs2"
XDG_CACHE_HOME=$t/cache3 "$t/zs2" build src/Main.zs --release -o "$t/zs3"
cmp -s "$t/zs2" "$t/zs3" || { echo "the compiler doesn't build itself to the same binary" >&2; exit 1; }
archive() { # binary name
  src/install.sh "$1" "$t/$2"
  mkdir -p dist
  tar -czf "dist/$2.tar.gz" -C "$t" "$2"
  echo "dist/$2.tar.gz"
}
archive "$t/zs3" "zs-$version-linux-$arch"
for target in "$@"; do
  a=${target%%-*}; os=${target#*-}; os=${os%%-*}
  exe=$t/zs-$target; [ "$os" = windows ] && exe=$exe.exe
  XDG_CACHE_HOME=$t/cache-$target "$t/zs3" build src/Main.zs --release --target "$target" -o "$exe"
  archive "$exe" "zs-$version-$os-$a"
done
