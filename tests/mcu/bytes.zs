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
  // a growing Writer's room (int's most); a tag checked in fixed time
  let key = String.bytes "key"
  let tag = Hmac.sha256 key (String.bytes "abc")
  println $"{Bytes.remaining (Bytes.writerOf Buffer.empty)} {Hmac.verify key (String.bytes "abc") tag} {Hmac.verify key (String.bytes "abd") tag}"
  // Binary's ints past 2^30, and i64s past 32 bits, as a host writes them (an int a host wrote
  // that doesn't fit 32 bits is an Error, not another number)
  let ints: result<list<int>, string> =
    Binary.ofBytes (Binary.toBytes [ 1073741824; 2147483647; -2147483648; -1073741825 ])
  let wide: i64 = 5000000000 // typed, so the literal is 64 bits here too
  let big: result<i64, string> = Binary.ofBytes (Binary.toBytes wide)
  let narrow: result<int, string> = Binary.ofBytes (Binary.toBytes wide)
  println $"{ints} {big} {narrow}"
  // numbers past 1e15 and below 1e-4 print as JSON numbers (an exponent), not inf or 0
  let numbers = [ JNumber 2.5e15; JNumber 3.0e-7; JNumber (-1.25e-5); JNumber 1.0e300; JNumber 0.5 ]
  println (Json.print (JArray numbers))
  // nesting at most 32 levels deep, where int is 32 bits: a 4 KB stack holds it
  let depth (n: int) =
    match Json.parse (String.repeat n "[" + String.repeat n "]") with
    | Ok _ -> "ok"
    | Error e -> e
  println $"{depth 32} {depth 33}"
  0
