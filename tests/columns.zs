// columns (0037): [<Derive(Columns)>] gives a record columns<'r>, an array of it stored field by
// field. c.[i] is a row and c.[i].f an element of one column; c.f is the column; a function over
// any columns needs no annotation.
[<Derive(Columns)>]
type Particle = { x: f32; age: f32; id: i64; name: string }

[<Derive(Columns)>]
type Pair<'a> = { first: u8; second: 'a }

type World = { tick: int; particles: columns<Particle> }

// generic over any columns: its constraint is inferred
let lastRow c = Columns.get c (Columns.length c - 1)

let oldest (ps: columns<Particle>) : f32 = Array.max ps.age

let make (n: int) : columns<Particle> =
  Columns.init n (fun i -> { x = f32 i; age = f32 (i * 10); id = i64 i; name = $"p{i}" })

let main () =
  let ps = make 4
  println $"{Columns.length ps} {ps.[2]} {ps.[1].name} {lastRow ps} {oldest ps} {Array.sum ps.x}"
  for p in ps do
    print $"{p.id}:{p.age} "
  println ""
  // a literal stays the row's
  let one = { x = f32 1.0; age = f32 2.0; id = i64 3; name = "one" }
  let twice = Columns.create 2 one
  println $"{Columns.length twice} {twice.[1].name} {Array.toList (Columns.toArray twice)}"
  let older = Columns.map (fun (p: Particle) -> { p with age = p.age + f32 1.0 }) ps
  println $"{Array.toList older.age} {Array.toList ps.age}"
  let pairs = Columns.ofArray [| { first = u8 1; second = "a" }; { first = u8 2; second = "b" } |]
  println $"{pairs.[1]} {Array.toList pairs.first} {lastRow pairs} {(Columns.set pairs 0 { first = u8 9; second = "z" }).[0]} {pairs.[0]}"
  let none : array<Particle> = [||]
  let empty = Columns.ofArray none
  println $"{Columns.length empty} {Array.length empty.name}"
  let w = { tick = 1; particles = ps }
  println $"{w.particles.[3].id} {w.particles.[0]} {(make 2).[1].age}"
  // a column is an array: a slice of it, and a vector's lanes
  println $"{Array.sum ps.age.[1..2]} {F32x4.load ps.x 0} {Array.toList (Array.map (fun a -> a * f32 2.0) ps.age)}"
  println $"{ps.[4].age}"
  0
