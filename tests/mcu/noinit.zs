// [<Section ".noinit">] on a chip (0014 item 12): a boot counter the reset handler neither
// copies nor zeroes, so it survives a reset (the AIRCR register's SYSRESETREQ), and a DMA-style
// Buffer at a 32-byte boundary; a magic word says whether the memory is the previous run's
[<Section ".noinit">]
let magic = ref (u32 0)

[<Section ".noinit">]
let boots = ref 0

[<Section ".noinit"; Align 32>]
let dma = Buffer.create 64 (u8 0)

let main () =
  if magic.Value <> u32 0xB007C0DE then
    magic.Value <- u32 0xB007C0DE
    boots.Value <- 0
    dma.[0] <- u8 1
  else
    dma.[0] <- dma.[0] + u8 1
  boots.Value <- boots.Value + 1
  println $"boot {boots.Value} dma {dma.[0]} room {Buffer.length dma}"
  if boots.Value < 3 then
    Mmio.write32 (usize 0xE000ED0C) (u32 0x05FA0004)
    while true do
      ()
  0
