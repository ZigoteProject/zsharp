// a 32-tap FIR filter over 1024 q15 samples (fixed point: the M0+ has no FPU), each tap's product
// added with one rounding and saturation, as CMSIS-DSP's q15 kernels do it; the filter allocates
// nothing (0015's exit test)
open Numerics

[<NoAlloc>]
let fir (taps: array<q15>) (x: array<q15>) =
  let mutable sum = 0
  for i in 31 .. Array.length x - 1 do
    let mutable acc = Q15.zero
    for k in 0 .. 31 do
      acc <- Q15.mulAdd taps.[k] x.[i - k] acc
    sum <- sum + int (Q15.raw acc)
  sum

let main () =
  let mutable taps = Array.create 32 Q15.zero
  for k in 0 .. 31 do
    taps.[k] <- Q15.ofRaw (i16 ((k + 1) * 62))
  let mutable x = Array.create 1024 Q15.zero
  for i in 0 .. 1023 do
    x.[i] <- Q15.ofRaw (i16 ((i % 17 - 8) * 4096))
  let t0 = Runtime.ticks ()
  let s = fir taps x
  let t1 = Runtime.ticks ()
  println $"firq15 result={s} ticks={t1 - t0}"
  0
