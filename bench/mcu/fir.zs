// a 32-tap FIR filter over 1024 f32 samples (single precision: the M4F's FPU)
let fir (taps: array<f32>) (x: array<f32>) =
  let mutable sum = f32 0.0
  for i in 31 .. Array.length x - 1 do
    let mutable acc = f32 0.0
    for k in 0 .. 31 do
      acc <- acc + taps.[k] * x.[i - k]
    sum <- sum + acc
  sum

let main () =
  let mutable taps = Array.create 32 (f32 0.0)
  for k in 0 .. 31 do
    taps.[k] <- f32 (k + 1) / f32 528.0
  let mutable x = Array.create 1024 (f32 0.0)
  for i in 0 .. 1023 do
    x.[i] <- f32 (i % 17) - f32 8.0
  let t0 = Runtime.ticks ()
  let s = fir taps x
  let t1 = Runtime.ticks ()
  println $"fir result={int (s * f32 1000.0)} ticks={t1 - t0}"
  0
