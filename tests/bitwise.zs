// Bitwise operators on integers: &&& ||| ^^^ <<< >>> ~~~
let crc8 (data: list<u8>) =
  let mutable crc = u8 0
  for b in data do
    crc <- crc ^^^ b
    for _ in 1 .. 8 do
      crc <- if crc &&& u8 0x80 <> u8 0 then (crc <<< u8 1) ^^^ u8 0x07 else crc <<< u8 1
  crc

let main () =
  println $"{0b1100 &&& 0b1010} {12 ||| 10} {12 ^^^ 10} {1 <<< 10} {1024 >>> 3} {~~~0}"
  println $"{-16 >>> 2} {u8 0xF0 >>> u8 4} {~~~(u8 0x0F)} {1 <<< 65}"
  let flags = 0x5
  println $"{flags &&& 0x4 <> 0} {flags &&& 0x2 = 0} {(flags ||| 0x2) &&& 0x2 <> 0}"
  println $"crc8 {crc8 [ u8 0x31; u8 0x32; u8 0x33 ]}"
  let deep: list<list<list<int>>> = [ [ [ 1 ] ] ]
  println $"{deep}"
  println $"{hash ("a long string to hash", "and another one") = hash ("a long string to hash", "and another one")}"
  0
