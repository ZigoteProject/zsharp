// b"…" byte strings, and C memory read without a hand-written loop: Ptr.readUnaligned,
// writeUnaligned and diff, a vector loaded at a pointer, and a span over it (track S, item 12)
let crlf = b"\r\n"

let main () =
  let header = b"Content-Length: 42\r\n"
  let colon = Option.get (Span.indexOf b":" header)
  println $"{Span.length header} {Span.indexOf crlf header} {Span.equalsIgnoreCase header.[..colon - 1] b"content-length"}"
  println $"{Span.parseInt (Span.trim header.[colon + 1 ..])}"
  // C memory: 16 bytes, written and read at an odd address
  let p: ptr<u8> = unsafe (Ptr.alloc 32)
  unsafe
    for i in 0 .. 31 do
      Ptr.write (Ptr.add p i) (u8 i)
    let odd: ptr<u64> = Ptr.cast (Ptr.add p 1)
    println $"{Ptr.readUnaligned odd}"
    Ptr.writeUnaligned odd (u64 0x1122334455667788)
    println $"{Ptr.read (Ptr.add p 1)} {Ptr.read (Ptr.add p 8)} {Ptr.diff (Ptr.add p 9) p}"
    let v: ptr<u8x16> = Ptr.cast (Ptr.add p 3)
    println $"{U8x16.sum (Ptr.readUnaligned v)}"
    let s = Span.ofPtr p 32
    println $"{Bytes.readU32BE s 12} {Span.indexOf [| u8 20; u8 21 |] s}"
    Ptr.free p
  // the writer: a response as a pipeline
  let body = "{\"msg\":\"tab\there \u{1}, quote \" and a long run of plain text past 16 bytes\"}"
  let out =
    Buffer.empty
    |> Bytes.append b"HTTP/1.1 200 OK\r\nContent-Length: "
    |> Bytes.appendInt (String.length body)
    |> Bytes.append b"\r\n\r\n"
    |> Bytes.appendUtf8 body
  println (String.replace (String.ofBytes out) "\r" "\\r")
  println (String.ofBytes (Bytes.appendJsonString body Buffer.empty))
  let ints =
    Buffer.empty
    |> Bytes.appendInt (1 <<< (8 * sizeof<int> -1))
    |> Bytes.append b" "
    |> Bytes.appendInt 7
  println (String.ofBytes ints)
  0
