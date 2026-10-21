// CRC-32 (bitwise, no table) over a 4 KB buffer, 10 times
let crc32 (data: array<u8>) =
  let mutable crc = u32 0xFFFFFFFF
  for i in 0 .. Array.length data - 1 do
    crc <- crc ^^^ u32 data.[i]
    for _ in 1 .. 8 do
      crc <- if crc &&& u32 1 <> u32 0 then (crc >>> u32 1) ^^^ u32 0xEDB88320 else crc >>> u32 1
  crc ^^^ u32 0xFFFFFFFF

let main () =
  let mutable data = Array.create 4096 (u8 0)
  for i in 0 .. 4095 do
    data.[i] <- u8 (i * 7 % 251)
  let t0 = Runtime.ticks ()
  let mutable crc = u32 0
  for _ in 1 .. 10 do
    crc <- crc32 data
  let t1 = Runtime.ticks ()
  println $"crc32 result={crc} ticks={t1 - t0}"
  0
