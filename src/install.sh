#!/usr/bin/env bash
# Installs a Z# compiler binary into a directory as zs expects to find itself: zs, the library
# (lib/), the runtime's C (rt.c, rt-embedded.c), the boards' linker scripts and interrupt tables
# (boards/) and the Node host for WebAssembly (run-wasm.mjs).
#   src/install.sh <zs binary> <directory>
# Both paths are the caller's, from where it runs. The directory is the compiler's own: its lib/
# and wepoll/ are replaced, so one whose lib/ or wepoll/ is something else (a prefix's, as
# /usr/local or ~/.local) is refused, as is the checkout, or what it copies from. A step that
# fails stops it.
set -eu
unset CDPATH
[ $# -eq 2 ] || { echo "usage: src/install.sh <zs binary> <directory>" >&2; exit 2; }
# absolute before the cd into the checkout
from=$(cd "$(dirname "$1")" && pwd)
zs=$from/$(basename "$1")
mkdir -p "$2"
dir=$(cd "$2" && pwd -P)
cd "$(dirname "$0")/.."
refuse() { echo "install.sh: $1; install into a directory of its own (bin, ~/.local/zs)" >&2; exit 1; }
here=$(pwd -P)
case $dir/ in
  "$here/" | "$here/lib/"* | "$here/runtime/"*) refuse "$2 is the checkout, or in its lib/ or runtime/" ;;
esac
if [ -e "$dir/lib" ] || [ -L "$dir/lib" ]; then
  [ -f "$dir/lib/prelude.zs" ] && [ -d "$dir/lib/core" ] || refuse "$dir/lib isn't a Z# library"
fi
if [ -e "$dir/wepoll" ] || [ -L "$dir/wepoll" ]; then
  [ -f "$dir/wepoll/wepoll.c" ] || refuse "$dir/wepoll isn't wepoll"
fi
name=zs; case $zs in *.exe) name=zs.exe ;; esac  # Windows's
cp "$zs" "$dir/$name.new"
mv "$dir/$name.new" "$dir/$name"
# each directory copied beside the old one and moved over it: a copy that fails leaves the old
rm -rf "$dir/lib.new" "$dir/wepoll.new"
cp -r lib "$dir/lib.new"
cp -r runtime/wepoll "$dir/wepoll.new"
rm -rf "$dir/lib" "$dir/wepoll"
mv "$dir/lib.new" "$dir/lib"
mv "$dir/wepoll.new" "$dir/wepoll"
cp runtime/rt.c runtime/rt-embedded.c runtime/run-wasm.mjs runtime/utf8.rc runtime/utf8.manifest "$dir/"
mkdir -p "$dir/boards"
cp runtime/boards/*.ld runtime/boards/*.irq "$dir/boards/"
