// Text.Utf8: bytes checked, decoded (malformed bytes as U+FFFD) and encoded
let bytesOf (xs: list<int>) : array<u8> = Array.ofList (List.map u8 xs)

let checked (r: result<unit, int>) =
  match r with
  | Ok() -> "ok"
  | Error at -> $"bad at {at}"

let main () =
  let good = String.bytes "héllo €𝄞"
  println $"{checked (Utf8.validate good)} {Utf8.tryDecode good}"
  // a stray continuation, an overlong form, a surrogate, a value past U+10FFFF, a cut sequence
  let malformed =
    [ [ 0x61; 0x80; 0x62 ]
      [ 0xC0; 0xAF ]
      [ 0xED; 0xA0; 0x80 ]
      [ 0xF4; 0x90; 0x80; 0x80 ]
      [ 0x61; 0xE2; 0x82 ] ]
  for bad in malformed do
    let b = bytesOf bad
    println $"{checked (Utf8.validate b)} {Utf8.tryDecode b} {Utf8.decode b}"
  let out = Buffer.empty
  for c in [ 'a'; 'é'; '€'; '𝄞' ] do
    Utf8.encodeChar c out
  println $"{Buffer.length out} {Utf8.decode (Buffer.toArray out)} {Utf8.decode (Buffer.toArray out) = "aé€𝄞"}"
  0
