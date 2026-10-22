// A 3 x 3 box blur with SIMD: each pixel inside a 2048 x 2048 f32 image becomes the mean of
// itself and its 8 neighbours, 8 pixels at a time with F32x8, 20 times over, between two images
// (the border stays as it was). Phase 8's exit test against blur.c, which uses AVX or NEON
// intrinsics.

// src blurred into dst (which the call takes, and gives back changed)
let blur (src: array<f32>) (dst: array<f32>) (w: int) (h: int) : array<f32> =
  let ninth = F32x8.splat (f32 1.0 / f32 9.0)
  let mutable out = dst
  for y in 1 .. h - 2 do
    let up = (y - 1) * w
    let row = y * w
    let down = (y + 1) * w
    // the pixels from 1 to last + 7, 8 at a time; then the rest of the row, one at a time
    let last = 1 + (w - 2) / 8 * 8 - 8
    for x in 1 .. 8 .. last do
      let a = F32x8.load src (up + x - 1) + F32x8.load src (up + x) + F32x8.load src (up + x + 1)
      let b = F32x8.load src (row + x - 1) + F32x8.load src (row + x) + F32x8.load src (row + x + 1)
      let c = F32x8.load src (down + x - 1) + F32x8.load src (down + x) + F32x8.load src (down + x + 1)
      out <- F32x8.store out (row + x) ((a + b + c) * ninth)
    for x in last + 8 .. w - 2 do
      let a = src.[up + x - 1] + src.[up + x] + src.[up + x + 1]
      let b = src.[row + x - 1] + src.[row + x] + src.[row + x + 1]
      let c = src.[down + x - 1] + src.[down + x] + src.[down + x + 1]
      out.[row + x] <- (a + b + c) / f32 9.0
  out

let main () =
  let w = 2048
  let h = 2048
  let image = Array.init (w * h) (fun i -> f32 ((i * 7919) % 256))
  let mutable a = image
  let mutable b = Array.copy image
  for _ in 1 .. 20 do
    let next = blur a b w h
    b <- a
    a <- next
  let mutable total = 0.0
  for i in 0 .. w * h - 1 do
    total <- total + float a.[i]
  println $"sum {total}"
