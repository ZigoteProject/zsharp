// N-body with SIMD: 1,024 bodies in arrays of f32 (one per coordinate), each one's acceleration
// summed over the others 8 at a time with F32x8, for 200 steps. Phase 8's exit test against
// nbody.c, which uses AVX or NEON intrinsics.
type Bodies =
  { x: array<f32>; y: array<f32>; z: array<f32>
    vx: array<f32>; vy: array<f32>; vz: array<f32>; m: array<f32> }

let step (b: Bodies) (dt: f32) : Bodies =
  let n = Array.length b.x
  let eps = F32x8.splat (f32 0.01)
  let one = F32x8.splat (f32 1.0)
  let mutable vx = b.vx
  let mutable vy = b.vy
  let mutable vz = b.vz
  for i in 0 .. n - 1 do
    let xi = F32x8.splat b.x.[i]
    let yi = F32x8.splat b.y.[i]
    let zi = F32x8.splat b.z.[i]
    let mutable ax = F32x8.splat (f32 0.0)
    let mutable ay = F32x8.splat (f32 0.0)
    let mutable az = F32x8.splat (f32 0.0)
    let mutable j = 0
    while j < n do
      let dx = F32x8.load b.x j - xi
      let dy = F32x8.load b.y j - yi
      let dz = F32x8.load b.z j - zi
      let d2 = F32x8.mulAdd dx dx (F32x8.mulAdd dy dy (F32x8.mulAdd dz dz eps))
      let f = F32x8.load b.m j * (one / (d2 * F32x8.sqrt d2))
      ax <- F32x8.mulAdd dx f ax
      ay <- F32x8.mulAdd dy f ay
      az <- F32x8.mulAdd dz f az
      j <- j + 8
    vx.[i] <- vx.[i] + F32x8.sum ax * dt
    vy.[i] <- vy.[i] + F32x8.sum ay * dt
    vz.[i] <- vz.[i] + F32x8.sum az * dt
  let (vx, vy, vz) = (vx, vy, vz)
  { b with
      x = Array.init n (fun i -> b.x.[i] + vx.[i] * dt)
      y = Array.init n (fun i -> b.y.[i] + vy.[i] * dt)
      z = Array.init n (fun i -> b.z.[i] + vz.[i] * dt)
      vx = vx; vy = vy; vz = vz }

let main () =
  let n = 1024
  let bodies =
    { x = Array.init n (fun i -> f32 (i % 16) + f32 0.1 * f32 (i % 5))
      y = Array.init n (fun i -> f32 (i / 16 % 16))
      z = Array.init n (fun i -> f32 (i / 256))
      vx = Array.create n (f32 0.0); vy = Array.create n (f32 0.0); vz = Array.create n (f32 0.0)
      m = Array.init n (fun i -> f32 1.0 + f32 (i % 3)) }
  let mutable b = bodies
  for _ in 1 .. 200 do
    b <- step b (f32 0.001)
  let mutable e = 0.0
  for i in 0 .. n - 1 do
    e <- e + 0.5 * float b.m.[i] * float (b.vx.[i] * b.vx.[i] + b.vy.[i] * b.vy.[i] + b.vz.[i] * b.vz.[i])
  println $"kinetic energy {e}"
