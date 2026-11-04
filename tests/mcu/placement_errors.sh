#!/usr/bin/env bash
# placement's rules on a chip (0014 item 12), each refused with its reason: a constant table in a
# section the board's script doesn't name (RAM never loaded from flash), a ref in flash, a
# constant in a section named .noinit… (as the scripts' *(.noinit*) takes it), and a library's
# placed value that needs startup work (a copy from flash, a .noinit ref's header); a library's
# .noinit Buffer and a host library's ref in a named section need none, and build
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t"
check() {
  printf '%s' "$3" > "$1.zs"
  if "$zs" build "$1.zs" $2 -o "$1.out" 2>"$1.log"; then echo "$1: built"; else echo "$1: $(grep -o 'error: .*' "$1.log" | head -1)"; fi
}
check table "--target cortex-m4" $'[<Section ".dma">]\nlet table = [| 1; 2; 3 |]\n\nlet main () =\n  println $"{table.[0]}"\n  0\n'
check flash "--target cortex-m4" $'[<Section ".rodata.boot">]\nlet boots = ref 0\n\nlet main () =\n  boots.Value <- boots.Value + 1\n  0\n'
check noinitlog "--target cortex-m4" $'[<Section ".noinit_log">]\nlet table = [| 1; 2; 3 |]\n\nlet main () =\n  println $"{table.[0]}"\n  0\n'
check dmalib "--lib --target cortex-m4" $'[<Section ".dma">]\nlet counter = ref 5\n\n[<Export>]\nlet bump (n: int) : int =\n  counter.Value <- counter.Value + n\n  counter.Value\n'
check noinitlib "--lib --target cortex-m4" $'[<Section ".noinit">]\nlet boots = ref 0\n\n[<Export>]\nlet bump (n: int) : int =\n  boots.Value <- boots.Value + n\n  boots.Value\n'
check bufferlib "--lib --target cortex-m4" $'[<Section ".noinit">]\nlet log = Buffer.create 4 (u8 0)\n\n[<Export>]\nlet first (n: int) : int = int log.[0] + n\n'
check hostlib "--lib" $'[<Section ".dma">]\nlet counter = ref 5\n\n[<Export>]\nlet bump (n: int) : int =\n  counter.Value <- counter.Value + n\n  counter.Value\n'
