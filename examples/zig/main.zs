// Zig from Z# through the C ABI (README.md): cryptokit/ is a Zig package wrapping its standard
// library's cryptography (BLAKE3, Ed25519, CRC-32) as a static library. Its functions take bytes
// as a pointer and a length, which is what a span is in an extern: a string's bytes, an array or
// a Buffer, the Buffer being where a result is written.
extern ck_crc32 : span<u8> -> u32
extern ck_blake3 : span<u8> -> span<u8> -> unit
extern ck_public_key : span<u8> -> span<u8> -> unit
extern ck_sign : span<u8> -> span<u8> -> span<u8> -> unit
extern ck_verify : span<u8> -> span<u8> -> span<u8> -> bool

// bytes in hex
let hex (bytes: Buffer<u8>) : string =
  String.concat (List.map (fun (b: u8) -> $"{b:x2}") (Array.toList (Buffer.toArray bytes)))

let main () =
  let image = String.bytes "firmware 1.2.0: blink every 500 ms"
  println $"crc32  {ck_crc32 image:X8}"
  let digest = Buffer.create 32 (u8 0)
  ck_blake3 image digest
  println $"blake3 {hex digest}"
  // a key pair from a seed (a real seed comes from a hardware RNG, and stays secret)
  let seed = Array.init 32 (fun i -> u8 (i * 7 + 1))
  let key = Buffer.create 32 (u8 0)
  ck_public_key seed key
  println $"public {hex key}"
  let signature = Buffer.create 64 (u8 0)
  ck_sign seed image signature
  println $"signed, verifies: {ck_verify key image signature}"
  println $"tampered, verifies: {ck_verify key (String.bytes "firmware 1.2.0: blink every 50 ms") signature}"
  0
