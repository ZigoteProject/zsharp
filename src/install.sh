#!/usr/bin/env bash
# Installs a Z# compiler binary into a directory as zs expects to find itself: zs, the library
# (lib/), the runtime's C (rt.c, rt-embedded.c) and the boards' linker scripts (boards/).
#   src/install.sh <zs binary> <directory>
set -eu
cd "$(dirname "$0")/.."
zs=$1; dir=$2
mkdir -p "$dir"
name=zs; case $zs in *.exe) name=zs.exe ;; esac  # Windows's
cp "$zs" "$dir/$name.new" && mv "$dir/$name.new" "$dir/$name"
rm -rf "$dir/lib" && cp -r lib "$dir/lib"
cp runtime/rt.c runtime/rt-embedded.c "$dir/"
rm -rf "$dir/wepoll" && cp -r runtime/wepoll "$dir/wepoll"
mkdir -p "$dir/boards" && cp runtime/boards/*.ld "$dir/boards/"
