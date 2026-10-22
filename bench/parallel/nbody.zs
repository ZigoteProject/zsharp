// N-body in parallel: n bodies attracting one another, each step's accelerations computed by
// the thread pool (O(n^2) a step), then the velocities and positions updated. Phase 7's exit
// test (with mandelbrot).

type Body = { x: float; y: float; z: float; vx: float; vy: float; vz: float; m: float }

// the acceleration on body i from the others
let accel (bodies: array<Body>) (i: int) : float * float * float =
  let b = bodies.[i]
  let mutable ax = 0.0
  let mutable ay = 0.0
  let mutable az = 0.0
  for j in 0 .. Array.length bodies - 1 do
    if j <> i then
      let o = bodies.[j]
      let dx = o.x - b.x
      let dy = o.y - b.y
      let dz = o.z - b.z
      let d2 = dx * dx + dy * dy + dz * dz + 0.01
      let f = o.m / (d2 * Math.sqrt d2)
      ax <- ax + dx * f
      ay <- ay + dy * f
      az <- az + dz * f
  (ax, ay, az)

let step (bodies: array<Body>) (dt: float) : array<Body> =
  let acc = Array.Parallel.init (Array.length bodies) (fun i -> accel bodies i)
  Array.init (Array.length bodies) (fun i ->
    let b = bodies.[i]
    let (ax, ay, az) = acc.[i]
    let vx = b.vx + ax * dt
    let vy = b.vy + ay * dt
    let vz = b.vz + az * dt
    { b with x = b.x + vx * dt; y = b.y + vy * dt; z = b.z + vz * dt; vx = vx; vy = vy; vz = vz })

let energy (bodies: array<Body>) =
  let mutable e = 0.0
  for b in Array.toList bodies do
    e <- e + 0.5 * b.m * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
  e

let main () =
  let n = match Environment.args () with
          | s :: _ -> Option.get (String.parseInt s)
          | _ -> 3000
  // bodies on a cube's grid, at rest
  let mutable s = 1
  while s * s * s < n do
    s <- s + 1
  let side = s
  let mutable bodies = Array.init n (fun i ->
    let gx = float (i % side)
    let gy = float (i / side % side)
    let gz = float (i / (side * side))
    { x = gx + 0.1 * float (i % 5); y = gy; z = gz; vx = 0.0; vy = 0.0; vz = 0.0; m = 1.0 + float (i % 3) })
  for _ in 1 .. 10 do
    bodies <- step bodies 0.001
  println $"kinetic energy after 10 steps: {energy bodies}"
