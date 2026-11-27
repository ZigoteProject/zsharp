// What proposal 0037 (columns) measures: loops over one or three fields of 4,000,000 records,
// as an array of records and as an array per field written by hand. Prints ns per element, the
// best of 15 rounds: zs build --release bench/columns/by_hand.zs -o by_hand && ./by_hand
type Particle =
  { x: f32
    y: f32
    z: f32
    vx: f32
    vy: f32
    vz: f32
    age: f32
    mass: f32
    id: i64
    lastSeen: i64
    flags: u32
    team: u32 }

type Columns =
  { xs: array<f32>
    ys: array<f32>
    zs: array<f32>
    vxs: array<f32>
    vys: array<f32>
    vzs: array<f32>
    ages: array<f32> }

let n = 4000000

let time (name: string) (rounds: int) (f: unit -> f32) =
  let mutable best = u64 0
  let mutable r = f32 0.0
  for i in 0 .. rounds - 1 do
    let t0 = Runtime.ticks ()
    r <- f ()
    let dt = Runtime.ticks () - t0
    if i = 0 || dt < best then best <- dt
  println $"{name}: {float best / float n} ns/element (result {r})"

[<FastMath>]
let sumAos (aos: array<Particle>) : f32 =
  let mutable s = f32 0.0
  for i in 0 .. n - 1 do
    s <- s + aos.[i].age
  s

[<FastMath>]
let sumOne (ages: array<f32>) : f32 =
  let mutable s = f32 0.0
  for i in 0 .. n - 1 do
    s <- s + ages.[i]
  s

let main () =
  let aos =
    Array.init n (fun i ->
      { x = f32 i; y = f32 1.0; z = f32 2.0; vx = f32 0.5; vy = f32 0.25; vz = f32 0.125
        age = f32 (i % 100)
        mass = f32 1.0
        id = i64 i
        lastSeen = i64 0
        flags = u32 0
        team = u32 (i % 4) })
  let soa =
    { xs = Array.init n (fun i -> f32 i)
      ys = Array.create n (f32 1.0)
      zs = Array.create n (f32 2.0)
      vxs = Array.create n (f32 0.5)
      vys = Array.create n (f32 0.25)
      vzs = Array.create n (f32 0.125)
      ages = Array.init n (fun i -> f32 (i % 100)) }
  println $"sizeof<Particle> = {sizeof<Particle>}"
  time "sum age, array of records" 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      s <- s + aos.[i].age
    s)
  time "sum age, one array      " 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      s <- s + soa.ages.[i]
    s)
  time "sum age FastMath, records " 15 (fun () -> sumAos aos)
  time "sum age FastMath, one array" 15 (fun () -> sumOne soa.ages)
  time "max age, array of records" 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      if aos.[i].age > s then s <- aos.[i].age
    s)
  time "max age, one array      " 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      if soa.ages.[i] > s then s <- soa.ages.[i]
    s)
  time "kinetic, array of records" 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      let p = aos.[i]
      s <- s + p.vx * p.vx + p.vy * p.vy + p.vz * p.vz
    s)
  time "kinetic, three arrays   " 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      s <- s + soa.vxs.[i] * soa.vxs.[i] + soa.vys.[i] * soa.vys.[i] + soa.vzs.[i] * soa.vzs.[i]
    s)
  0
