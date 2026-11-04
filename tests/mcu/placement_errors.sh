#!/usr/bin/env bash
# placement's rules on a chip (0014 item 12), each refused with its reason: a constant table in a
# section the board's script doesn't name that holds a ref too (writable, so RAM, never loaded
# from flash), a ref in flash, a constant in a section named .noinit… (as the scripts'
# *(.noinit*) takes it) or .bss… (zeroed), a ref in .bss that doesn't start at zero, anything in
# the board's own .vectors (the vector table starts the image), and a chip library's placed value
# that needs startup work (a copy from flash, a .noinit ref's header). A plain union's first case
# is zeros, so it's fine in .bss.
# A constant alone in a section of its own (read-only: the linker keeps it in flash), a zero ref
# or Buffer in .bss, a library's .noinit Buffer, and a host library's placed refs need none, and
# build
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t"
check() {
  printf '%s' "$3" > "$1.zs"
  if "$zs" build "$1.zs" $2 -o "$1.out" 2>"$1.log"; then echo "$1: built"; else echo "$1: $(grep -o 'error: .*' "$1.log" | head -1)"; fi
}
check table "--target cortex-m4" $'[<Section ".dma">]\nlet table = [| 1; 2; 3 |]\n\nlet main () =\n  println $"{table.[0]}"\n  0\n'
check shared "--target cortex-m4" $'[<Section ".dma">]\nlet table = [| 1; 2; 3 |]\n\n[<Section ".dma">]\nlet count = ref 0\n\nlet main () =\n  count.Value <- table.[0]\n  0\n'
check bsstable "--target cortex-m4" $'[<Section ".bss">]\nlet table = [| 1; 2; 3 |]\n\nlet main () =\n  println $"{table.[0]}"\n  0\n'
check bssfive "--target cortex-m4" $'[<Section ".bss">]\nlet count = ref 5\n\nlet main () =\n  count.Value <- count.Value + 1\n  0\n'
check bssunion "--target cortex-m4" $'type Mode =\n  | Off\n  | On\n\n[<Section ".bss">]\nlet modes = Buffer.create 4 Off\n\n[<Section ".bss.o">]\nlet pending = ref (None: option<int>)\n\nlet main () =\n  modes.[1] <- On\n  pending.Value <- Some 4\n  0\n'
check vectors "--target cortex-m4" $'[<Section ".vectors">]\nlet table = [| 1; 2; 3 |]\n\nlet main () =\n  println $"{table.[0]}"\n  0\n'
check vectorsref "--target cortex-m4" $'[<Section ".vectors">]\nlet count = ref 5\n\nlet main () =\n  count.Value <- count.Value + 1\n  0\n'
check bsslib "--lib --target cortex-m4" $'[<Section ".bss.dma">]\nlet rx = Buffer.create 16 (u8 0)\n\n[<Section ".bss">]\nlet count = ref 0\n\n[<Export>]\nlet take (n: int) : int =\n  count.Value <- count.Value + n\n  int rx.[0] + count.Value\n'
check flash "--target cortex-m4" $'[<Section ".rodata.boot">]\nlet boots = ref 0\n\nlet main () =\n  boots.Value <- boots.Value + 1\n  0\n'
check noinitlog "--target cortex-m4" $'[<Section ".noinit_log">]\nlet table = [| 1; 2; 3 |]\n\nlet main () =\n  println $"{table.[0]}"\n  0\n'
check dmalib "--lib --target cortex-m4" $'[<Section ".dma">]\nlet counter = ref 5\n\n[<Export>]\nlet bump (n: int) : int =\n  counter.Value <- counter.Value + n\n  counter.Value\n'
check noinitlib "--lib --target cortex-m4" $'[<Section ".noinit">]\nlet boots = ref 0\n\n[<Export>]\nlet bump (n: int) : int =\n  boots.Value <- boots.Value + n\n  boots.Value\n'
check bufferlib "--lib --target cortex-m4" $'[<Section ".noinit">]\nlet log = Buffer.create 4 (u8 0)\n\n[<Export>]\nlet first (n: int) : int = int log.[0] + n\n'
check hostnoinit "--lib" $'[<Section ".noinit">]\nlet boots = ref 0\n\n[<Export>]\nlet bump (n: int) : int =\n  boots.Value <- boots.Value + n\n  boots.Value\n'
check hostlib "--lib" $'[<Section ".dma">]\nlet counter = ref 5\n\n[<Export>]\nlet bump (n: int) : int =\n  counter.Value <- counter.Value + n\n  counter.Value\n'
