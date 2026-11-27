// ColumnBuffer (0037, step 4): [<Derive(Columns)>] gives a record ColumnBuffer<'r> beside its
// columns, a Buffer per field. b.[i] is a row and b.[i].f an element of one column; b.f is the
// column, a Buffer; writes go through any binding and are seen through every reference; push,
// pop and truncate change every column at once. Checked against a Buffer of rows as a model.
open Testing

[<Derive(Columns)>]
type Particle = { x: f32; age: f32; id: i64; name: string }

[<Derive(Columns)>]
type Pair<'a> = { first: u8; second: 'a }

type World = { tick: int; particles: ColumnBuffer<Particle> }

[<Derive(Arbitrary)>]
type Command =
  | Push of int
  | Pop
  | Set of int * int
  | SetAge of int * int
  | Truncate of int
  | Clear

// generic over any ColumnBuffer: its constraint is inferred
let lastRow b = ColumnBuffer.get b (ColumnBuffer.length b - 1)

let particle (i: int) = { x = f32 i; age = f32 (i * 10); id = i64 i; name = $"p{i}" }

// an index in 0 .. n - 1 from any int (abs of the smallest int overflows)
let wrap (i: int) (n: int) = ((i % n) + n) % n

let ages (b: ColumnBuffer<Particle>) = Buffer.toArray b.age |> Array.toList

// one command on the system and on the model; their rows must agree after each
let step (c: Command) (pair: ColumnBuffer<Particle> * Buffer<Particle>) : result<ColumnBuffer<Particle> * Buffer<Particle>, string> =
  let (sys, model) = pair
  let n = Buffer.length model
  let popped =
    match c with
    | Push i ->
      ColumnBuffer.push (particle i) sys
      Buffer.push (particle i) model
      Ok()
    | Pop ->
      let got = ColumnBuffer.pop sys
      let want = Buffer.pop model
      if got = want then Ok() else Error $"pop gives {got}, the model {want}"
    | Set(i, v) when n > 0 ->
      let at = wrap i n
      ColumnBuffer.set sys at (particle v)
      model.[at] <- particle v
      Ok()
    | SetAge(i, v) when n > 0 ->
      let at = wrap i n
      sys.[at].age <- f32 v
      model.[at] <- { model.[at] with age = f32 v }
      Ok()
    | Truncate k ->
      // to a count up to two past the length: past it, nothing changes
      ColumnBuffer.truncate (wrap k (n + 3)) sys
      Buffer.truncate (wrap k (n + 3)) model
      Ok()
    | Clear ->
      ColumnBuffer.clear sys
      Buffer.clear model
      Ok()
    | _ -> Ok()
  let rows = ColumnBuffer.toArray sys |> Array.toList
  let want = Buffer.toArray model |> Array.toList
  let lengths =
    [ Buffer.length sys.x; Buffer.length sys.age; Buffer.length sys.id; Buffer.length sys.name ]
  match popped with
  | Error e -> Error e
  | Ok() when rows <> want -> Error $"the buffer holds {rows}, the model {want}"
  | Ok() when List.exists (fun l -> l <> Buffer.length model) lengths ->
    Error $"columns of lengths {lengths}"
  | Ok() -> Ok(sys, model)

let main () =
  let b : ColumnBuffer<Particle> = ColumnBuffer.empty ()
  for i in 0 .. 3 do
    ColumnBuffer.push (particle i) b
  println $"{ColumnBuffer.length b} {b.[2]} {b.[1].name} {lastRow b}"
  // a write through one reference is seen through another
  let alias = b
  b.[1].age <- f32 99.0
  b.[2].id += i64 40
  alias.[3] <- { x = f32 -1.0; age = f32 -2.0; id = i64 -3; name = "last" }
  println $"{alias.[1].age} {alias.[2].id} {b.[3]} {ages b}"
  // a column is a Buffer, shared with the ColumnBuffer
  let names = b.name
  names.[0] <- "zero"
  println $"{b.[0].name} {Buffer.length b.x} {Array.sum (Buffer.toArray b.x)}"
  for p in b do
    print $"{p.id}:{p.age} "
  println ""
  println $"{ColumnBuffer.pop b} {ColumnBuffer.length b} {ages b}"
  // to and from columns, each a copy
  let cols = ColumnBuffer.toColumns b
  b.[0].age <- f32 7.0
  let again = ColumnBuffer.ofColumns cols
  println $"{Array.toList cols.age} {ages again} {ages b}"
  let made = ColumnBuffer.create 2 (particle 5)
  println $"{ColumnBuffer.length made} {made.[1]}"
  ColumnBuffer.clear made
  println $"{ColumnBuffer.length made} {ColumnBuffer.pop made}"
  // a generic row, from an array of rows
  let pairs =
    ColumnBuffer.ofArray [| { first = u8 1; second = "a" }; { first = u8 2; second = "b" } |]
  ColumnBuffer.push { first = u8 3; second = "c" } pairs
  println $"{pairs.[2]} {lastRow pairs} {Buffer.toArray pairs.first |> Array.toList}"
  // in a record's field, written without a let mutable
  let w = { tick = 0; particles = ColumnBuffer.create 3 (particle 1) }
  w.particles.[2].name <- "w"
  ColumnBuffer.push (particle 8) w.particles
  println $"{w.particles.[2].name} {ColumnBuffer.length w.particles}"
  // and through what isn't a variable: an element of an array, a call's result, a ref's Value
  let held = [| w.particles |]
  held.[0].[0].name <- "held"
  let get () = w.particles
  (get ()).[1] <- particle 6
  let r = ref w.particles
  r.Value.[3].age <- f32 -5.0
  println $"{w.particles.[0].name} {w.particles.[1].id} {w.particles.[3].age}"
  let against : Model<Command, ColumnBuffer<Particle>, Buffer<Particle>> =
    { init = (fun () -> (ColumnBuffer.empty (), Buffer.empty)); step = step }
  Testing.runAll [
    testPropertyWith { seed = Some (u64 7) } "a ColumnBuffer agrees with a Buffer of rows" (fun (commands: list<Command>) ->
      Prop.model commands against)
  ] |> ignore
  println $"{b.[9].age}"
  0
