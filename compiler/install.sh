#!/usr/bin/env bash
# Installs a Z# compiler binary into a directory as zs expects to find itself: zs, the library
# (lib/), the runtime's C (rt.c, rt-embedded.c) and the boards' linker scripts (boards/).
#   compiler/install.sh <zs binary> <directory>
set -eu
cd "$(dirname "$0")/.."
zs=$1; dir=$2
mkdir -p "$dir"
cp "$zs" "$dir/zs.new" && mv "$dir/zs.new" "$dir/zs"
rm -rf "$dir/lib" && cp -r lib "$dir/lib"
cp runtime/rt.c runtime/rt-embedded.c "$dir/"
mkdir -p "$dir/boards" && cp runtime/boards/*.ld "$dir/boards/"
