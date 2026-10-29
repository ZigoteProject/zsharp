/// SHA-256 (FIPS 180-4): a 32-byte digest of any bytes, on every target.
module Sha256

// the round constants, a match rather than an array: a top-level array would be computed at
// startup, which a library and a --no-heap program don't have
let private k (t: int) : u32 =
  match t with
  | 0 -> u32 0x428a2f98
  | 1 -> u32 0x71374491
  | 2 -> u32 0xb5c0fbcf
  | 3 -> u32 0xe9b5dba5
  | 4 -> u32 0x3956c25b
  | 5 -> u32 0x59f111f1
  | 6 -> u32 0x923f82a4
  | 7 -> u32 0xab1c5ed5
  | 8 -> u32 0xd807aa98
  | 9 -> u32 0x12835b01
  | 10 -> u32 0x243185be
  | 11 -> u32 0x550c7dc3
  | 12 -> u32 0x72be5d74
  | 13 -> u32 0x80deb1fe
  | 14 -> u32 0x9bdc06a7
  | 15 -> u32 0xc19bf174
  | 16 -> u32 0xe49b69c1
  | 17 -> u32 0xefbe4786
  | 18 -> u32 0x0fc19dc6
  | 19 -> u32 0x240ca1cc
  | 20 -> u32 0x2de92c6f
  | 21 -> u32 0x4a7484aa
  | 22 -> u32 0x5cb0a9dc
  | 23 -> u32 0x76f988da
  | 24 -> u32 0x983e5152
  | 25 -> u32 0xa831c66d
  | 26 -> u32 0xb00327c8
  | 27 -> u32 0xbf597fc7
  | 28 -> u32 0xc6e00bf3
  | 29 -> u32 0xd5a79147
  | 30 -> u32 0x06ca6351
  | 31 -> u32 0x14292967
  | 32 -> u32 0x27b70a85
  | 33 -> u32 0x2e1b2138
  | 34 -> u32 0x4d2c6dfc
  | 35 -> u32 0x53380d13
  | 36 -> u32 0x650a7354
  | 37 -> u32 0x766a0abb
  | 38 -> u32 0x81c2c92e
  | 39 -> u32 0x92722c85
  | 40 -> u32 0xa2bfe8a1
  | 41 -> u32 0xa81a664b
  | 42 -> u32 0xc24b8b70
  | 43 -> u32 0xc76c51a3
  | 44 -> u32 0xd192e819
  | 45 -> u32 0xd6990624
  | 46 -> u32 0xf40e3585
  | 47 -> u32 0x106aa070
  | 48 -> u32 0x19a4c116
  | 49 -> u32 0x1e376c08
  | 50 -> u32 0x2748774c
  | 51 -> u32 0x34b0bcb5
  | 52 -> u32 0x391c0cb3
  | 53 -> u32 0x4ed8aa4a
  | 54 -> u32 0x5b9cca4f
  | 55 -> u32 0x682e6ff3
  | 56 -> u32 0x748f82ee
  | 57 -> u32 0x78a5636f
  | 58 -> u32 0x84c87814
  | 59 -> u32 0x8cc70208
  | 60 -> u32 0x90befffa
  | 61 -> u32 0xa4506ceb
  | 62 -> u32 0xbef9a3f7
  | _ -> u32 0xc67178f2

let private rotr (x: u32) (n: u32) = (x >>> n) ||| (x <<< (u32 32 - n))

// one 64-byte block from `at` of `block` mixed into the state `h`
[<Wrapping>]
let private compress (h: Buffer<u32>) (w: Buffer<u32>) (block: span<u8>) (at: int) =
  for t in 0 .. 15 do
    let i = at + 4 * t
    w.[t] <- (u32 block.[i] <<< u32 24) ||| (u32 block.[i + 1] <<< u32 16) ||| (u32 block.[i + 2] <<< u32 8) ||| u32 block.[i + 3]
  for t in 16 .. 63 do
    let a = w.[t - 15]
    let b = w.[t - 2]
    let s0 = rotr a (u32 7) ^^^ rotr a (u32 18) ^^^ (a >>> u32 3)
    let s1 = rotr b (u32 17) ^^^ rotr b (u32 19) ^^^ (b >>> u32 10)
    w.[t] <- w.[t - 16] + s0 + w.[t - 7] + s1
  let mutable a = h.[0]
  let mutable b = h.[1]
  let mutable c = h.[2]
  let mutable d = h.[3]
  let mutable e = h.[4]
  let mutable f = h.[5]
  let mutable g = h.[6]
  let mutable hh = h.[7]
  for t in 0 .. 63 do
    let s1 = rotr e (u32 6) ^^^ rotr e (u32 11) ^^^ rotr e (u32 25)
    let ch = (e &&& f) ^^^ (~~~ e &&& g)
    let t1 = hh + s1 + ch + k t + w.[t]
    let s0 = rotr a (u32 2) ^^^ rotr a (u32 13) ^^^ rotr a (u32 22)
    let maj = (a &&& b) ^^^ (a &&& c) ^^^ (b &&& c)
    let t2 = s0 + maj
    hh <- g
    g <- f
    f <- e
    e <- d + t1
    d <- c
    c <- b
    b <- a
    a <- t1 + t2
  h.[0] <- h.[0] + a
  h.[1] <- h.[1] + b
  h.[2] <- h.[2] + c
  h.[3] <- h.[3] + d
  h.[4] <- h.[4] + e
  h.[5] <- h.[5] + f
  h.[6] <- h.[6] + g
  h.[7] <- h.[7] + hh

/// The SHA-256 digest of the bytes, 32 bytes.
///
/// ```zsharp
/// println (Hex.encode (Sha256.hash (String.bytes "abc")))
/// // => ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
/// ```
let hash (data: span<u8>) : array<u8> =
  let h =
    Buffer.ofArray [| u32 0x6a09e667;
      u32 0xbb67ae85;
      u32 0x3c6ef372;
      u32 0xa54ff53a;
      u32 0x510e527f;
      u32 0x9b05688c;
      u32 0x1f83d9ab;
      u32 0x5be0cd19 |]
  let w = Buffer.create 64 (u32 0)
  let n = Array.length data
  let mutable at = 0
  while at + 64 <= n do
    compress h w data at
    at <- at + 64
  // the last bytes, a 1 bit, zeros, and the length in bits: one block or two
  let tail = Buffer.create (if n - at < 56 then 64 else 128) (u8 0)
  for i in 0 .. n - at - 1 do
    tail.[i] <- data.[at + i]
  tail.[n - at] <- u8 0x80
  let bits = u64 n * u64 8
  for i in 0 .. 7 do
    tail.[Buffer.length tail - 1 - i] <- u8 (bits >>> u64 (8 * i))
  compress h w tail 0
  if Buffer.length tail = 128 then
    compress h w tail 64
  Array.init 32 (fun i -> u8 (h.[i / 4] >>> u32 (24 - 8 * (i % 4))))
