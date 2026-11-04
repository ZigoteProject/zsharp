// a ref and a Buffer in a section the board's script doesn't name (a DMA region): on a chip the
// reset handler doesn't load it, so the startup code copies their storage from flash
[<Section ".dma">]
let counter = ref 5

[<Section ".dma"; Align 32>]
let window = Buffer.create 4 (u16 7)

let main () =
  counter.Value <- counter.Value + 1
  window.[1] <- u16 9
  println $"{counter.Value} {window.[0]} {window.[1]} {Buffer.length window}"
  0
