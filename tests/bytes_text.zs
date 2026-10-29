// Bytes, Hex, Base64, Sha256, Hmac and the byte functions of Span (track S, items 12 and 13)
let show (o: option<array<u8>>) =
  match o with
  | Some b -> Hex.encode b
  | None -> "None"

let main () =
  let data = [| u8 0x12; u8 0x34; u8 0x56; u8 0x78; u8 0x9A; u8 0xBC; u8 0xDE; u8 0xF0 |]
  println $"{Bytes.readU16BE data 0} {Bytes.readU16LE data 0} {Bytes.readU32BE data 1} {Bytes.readU32LE data 4}"
  println $"{Bytes.readU64BE data 0} {Bytes.readI16BE data 4} {Bytes.readI32LE data 4} {Bytes.readI64BE data 0}"
  let out = Buffer.create 8 (u8 0)
  Bytes.writeU32BE out 0 (u32 0xDEADBEEF)
  Bytes.writeI16LE out 4 (i16 -2)
  Bytes.writeU16BE out 6 (u16 513)
  println (Hex.encode out)
  println $"{show (Hex.decode "00aBfF")} {show (Hex.decode "abc")} {show (Hex.decode "zz")}"
  for s in [ ""; "f"; "fo"; "foo"; "foob"; "fooba"; "foobar" ] do
    let e = Base64.encode (String.bytes s)
    let back =
      match Base64.decode e with
      | Some b -> String.ofBytes b
      | None -> "?"
    println $"'{s}' {e} {Base64.encodeUrl (String.bytes s)} {back = s}"
  println $"{show (Base64.decodeUrl "-_8")} {show (Base64.decode "-_8=")} {show (Base64.decode "Zm9=")} {show (Base64.decode "Zg")}"
  println (Hex.encode (Sha256.hash [||]))
  println (Hex.encode (Sha256.hash (String.bytes "abc")))
  println (Hex.encode (Sha256.hash (String.bytes "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))
  println (Hex.encode (Sha256.hash (Array.create 1000 (u8 97))))
  let fox = String.bytes "The quick brown fox jumps over the lazy dog"
  println (Hex.encode (Hmac.sha256 (String.bytes "key") fox))
  println (Hex.encode (Hmac.sha256 (Array.create 100 (u8 0xAA)) fox))
  let req = String.bytes "GET / HTTP/1.1\r\nContent-Length:  42 \r\n\r\n"
  println $"{Span.indexOf (String.bytes "\r\n\r\n") req} {Span.indexOf (String.bytes "xyz") req} {Span.startsWith (String.bytes "GET ") req}"
  let header = req.[16..38]
  let colon = Option.get (Span.indexOf (String.bytes ":") header)
  let value = Span.trim header.[colon + 1 ..]
  println $"{Span.equalsIgnoreCase header.[..colon - 1] (String.bytes "content-length")} {Span.parseInt value} {String.ofBytes value}"
  println $"{Span.parseInt (String.bytes "-9223372036854775808")} {Span.parseInt (String.bytes "9223372036854775808")} {Span.parseInt (String.bytes "+7")} {Span.parseInt (String.bytes "-")}"
  0
