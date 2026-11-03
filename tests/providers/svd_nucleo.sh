#!/usr/bin/env bash
# Track P's exit test (0001): examples/mcu/nucleo-f401.zs, rewritten on the STM32F401's SVD as
# nucleo-f401-svd.zs, compiles to the same register accesses: each volatile load and store of
# the two firmwares' LLVM IR, by address, as a multiset
zs=$(realpath "${1:-bin/zs}"); dir=$(mktemp -d)
cd "$(dirname "$0")/../.."
accesses() {
  # "load 0x40020000" / "store 0x40020018", sorted; a non-zero exit from the link is fine here
  ZS_NO_SERVER=1 "$zs" build "$1" --target nucleo-f401 -Os --emit-llvm -o "$dir/$2" >/dev/null 2>&1 || true
  # optimized, so each access is at its immediate address (the IR as written keeps them in
  # temporaries); opt is LLVM's, beside clang
  opt -O2 -S "$dir/$2.ll" | grep -oE '(load|store) volatile [^,]*, ptr inttoptr \(i32 [0-9]+' | sed -E 's/ volatile [^,]*, ptr inttoptr \(i32 / /' \
    | awk '{ printf "%s 0x%x\n", $1, $2 }' | sort
}
accesses examples/mcu/nucleo-f401.zs mmio > "$dir/mmio.txt"
accesses examples/mcu/nucleo-f401-svd.zs svd > "$dir/svd.txt"
if [ ! -s "$dir/mmio.txt" ]; then echo "no IR from examples/mcu/nucleo-f401.zs"; exit 1; fi
if diff "$dir/mmio.txt" "$dir/svd.txt"; then echo "the same $(wc -l < "$dir/mmio.txt") register accesses"; else echo "the accesses differ"; exit 1; fi
rm -rf "$dir"
