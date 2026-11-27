// The loops of by_hand.zs over columns<Particle> (proposal 0037), to hold beside its arrays by
// hand: ns per element, the best of 15 rounds.
// zs build --release bench/columns/columns.zs -o columns && ./columns
[<Derive(Columns)>]
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

let n = 4000000

let time (name: string) (rounds: int) (f: unit -> f32) =
  let mutable best = u64 0
  let mutable r = f32 0.0
  for i in 0 .. rounds - 1 do
    let t0 = Runtime.ticks ()
    r <- f ()
    let dt = Runtime.ticks () - t0
    if i = 0 || dt < best then
      best <- dt
  println $"{name}: {float best / float n} ns/element (result {r})"

[<FastMath>]
let sumFast (ages: array<f32>) : f32 =
  let mutable s = f32 0.0
  for i in 0 .. n - 1 do
    s <- s + ages.[i]
  s

let step (dt: f32) (ps: columns<Particle>) : columns<Particle> =
  let mutable ps = ps
  for i in 0 .. n - 1 do
    ps.[i].x <- ps.[i].x + ps.[i].vx * dt
    ps.[i].age <- ps.[i].age + dt
  ps

let stepArray (dt: f32) (ps: array<Particle>) : array<Particle> =
  let mutable ps = ps
  for i in 0 .. n - 1 do
    let p = ps.[i]
    ps.[i] <- { p with x = p.x + p.vx * dt; age = p.age + dt }
  ps

let main () =
  let rows =
    Array.init n (fun i ->
      { x = f32 i
        y = f32 1.0
        z = f32 2.0
        vx = f32 0.5
        vy = f32 0.25
        vz = f32 0.125
        age = f32 (i % 100)
        mass = f32 1.0
        id = i64 i
        lastSeen = i64 0
        flags = u32 0
        team = u32 (i % 4) })
  let ps = Columns.ofArray rows
  time "sum age, columns        " 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      s <- s + ps.[i].age
    s)
  time "sum age FastMath, column" 15 (fun () -> sumFast ps.age)
  time "max age, columns        " 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      if ps.[i].age > s then
        s <- ps.[i].age
    s)
  time "kinetic, columns        " 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      s <- s + ps.[i].vx * ps.[i].vx + ps.[i].vy * ps.[i].vy + ps.[i].vz * ps.[i].vz
    s)
  time "kinetic by rows, columns" 15 (fun () ->
    let mutable s = f32 0.0
    for i in 0 .. n - 1 do
      let p = ps.[i]
      s <- s + p.vx * p.vx + p.vy * p.vy + p.vz * p.vz
    s)
  // a step's result is the next step's argument, so each finds its columns held once
  let rec steps (k: int) (ps: columns<Particle>) : columns<Particle> =
    if k = 0 then ps else steps (k - 1) (step (f32 0.5) ps)
  let rec stepsArray (k: int) (ps: array<Particle>) : array<Particle> =
    if k = 0 then ps else stepsArray (k - 1) (stepArray (f32 0.5) ps)
  let warm = steps 1 ps
  let t0 = Runtime.ticks ()
  let moved = steps 10 warm
  let t1 = Runtime.ticks ()
  let warmRows = stepsArray 1 rows
  let t2 = Runtime.ticks ()
  let movedRows = stepsArray 10 warmRows
  let t3 = Runtime.ticks ()
  println $"step, columns           : {float (t1 - t0) / float (10 * n)} ns/element"
  println $"step, array of records  : {float (t3 - t2) / float (10 * n)} ns/element"
  println $"{moved.[n - 1].x} {movedRows.[n - 1].x}"
  0
