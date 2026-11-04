// a placed Buffer and ref in a program with no heap at all (--no-heap): static storage, so they
// build and run with nothing allocated; the exit report has only the stack
[<Section ".noinit"; Align 32>]
let frame = Buffer.create 64 (u8 0)

[<Section ".noinit">]
let boots = ref 0

let main () =
  frame.[0] <- u8 3
  boots.Value <- boots.Value + int frame.[0]
  0
