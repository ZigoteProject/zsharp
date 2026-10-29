// Bytes, Hex, Base64, Sha256, Hmac and Span's byte functions on a chip, where int is 32 bits:
// a host's results
let main () =
  let data = [| u8 0x12; u8 0x34; u8 0x56; u8 0x78; u8 0x9A; u8 0xBC; u8 0xDE; u8 0xF0 |]
  println $"{Bytes.readU32BE data 1} {Bytes.readI32LE data 4} {Bytes.readU64BE data 0}"
  println (Base64.encode (String.bytes "foobar"))
  println (Hex.encode (Sha256.hash (String.bytes "abc")))
  println (Hex.encode (Hmac.sha256 (String.bytes "key") (String.bytes "The quick brown fox jumps over the lazy dog")))
  println $"{Span.parseInt (String.bytes "-2147483648")} {Span.parseInt (String.bytes "2147483648")}"
  let mem: ptr<u8> = unsafe (Ptr.alloc 64)
  let out =
    unsafe (Bytes.writer mem 64)
    |> Bytes.append b"len="
    |> Bytes.appendInt (1 <<< 31)
    |> Bytes.append b" "
  println (String.ofBytes (Bytes.written (Bytes.appendJsonString "a \"quoted\" line of more than sixteen bytes\n" out)))
  println $"{Bytes.readF64BE (Bytes.written (Bytes.writerOf Buffer.empty |> Bytes.append [| u8 0x3F; u8 0xF8; u8 0; u8 0; u8 0; u8 0; u8 0; u8 0 |])) 0} {Float.ofBits32 (u32 0x40490fdb)}"
  unsafe (Ptr.free mem)
  0
