// columns (0037) are a value, as an array is: a write is in place where the columns are held
// once, and never seen through another name. In a let mutable each column is a variable of its
// own, so an element's write allocates nothing; in a let mutable record's field the array is
// taken out for the write, which is in place too.
[<Derive(Columns)>]
type Particle = { x: f32; age: f32; id: i64; name: string }

type World = { tick: int; particles: columns<Particle> }

let make (n: int) : columns<Particle> =
  Columns.init n (fun i -> { x = f32 i; age = f32 (i * 10); id = i64 i; name = $"p{i}" })

let step (dt: f32) (ps: columns<Particle>) : columns<Particle> =
  let mutable ps = ps
  for i in 0 .. Columns.length ps - 1 do
    ps.[i].x <- ps.[i].x + dt
    ps.[i].age += dt
  ps

let main () =
  let mutable ps = make 4
  let alias = ps
  ps.[1].age <- f32 99.0
  ps.[1].name <- "renamed"
  ps.[2].id += i64 40
  ps.[3] <- { x = f32 -1.0; age = f32 -2.0; id = i64 -3; name = "last" }
  println $"{ps.[1]} {ps.[2].id} {ps.[3]}"
  println $"{alias.[1]} {alias.[2].id} {alias.[3]}"
  // the whole, read and assigned
  let snapshot = ps
  ps <- step (f32 0.5) ps
  println $"{Array.toList ps.x} {Array.toList snapshot.x} {Array.toList ps.age}"
  ps <- alias
  println $"{ps.[3].name} {Columns.length ps}"
  // a fresh one filled in place: no allocation per write
  let n = 1000
  let mutable big = make n
  let before = Runtime.allocations ()
  for i in 0 .. n - 1 do
    big.[i].age <- big.[i].x * f32 2.0
    big.[i].id <- i64 (n - i)
  let made = Runtime.allocations () - before
  println $"{Array.sum big.age} {big.[0].id} {made}"
  // in a let mutable record
  let mutable w = { tick = 0; particles = make n }
  let kept = w.particles
  let before = Runtime.allocations ()
  for i in 0 .. n - 1 do
    w.particles.[i].age <- f32 1.0
  let copied = Runtime.allocations () - before
  w.particles.[0] <- { x = f32 7.0; age = f32 8.0; id = i64 9; name = "w" }
  println $"{Array.sum w.particles.age} {w.particles.[0]} {kept.[0].name} {Array.sum kept.age} {copied}"
  // an array in a let mutable record's field is written in place as well
  let mutable held = { tick = 0; particles = make 1 }
  held.tick <- 5
  println $"{held.tick} {held.particles.[0].name}"
  println $"{ps.[9].age}"
  0
