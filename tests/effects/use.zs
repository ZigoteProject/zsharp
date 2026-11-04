// use under effects (track S, item 10): a throw, or any clause that stops without resuming,
// disposes what the uses it passes over bound, newest first, before its handler's clause runs; a
// handler inside the scope keeps the scope whole; a clause that resumes runs the rest, which
// disposes at the scope's end as always
type Res = { name: string }

impl Dispose<Res> =
  let dispose (r: Res) = println $"  dispose {r.name}"

let step (n: int) : int / Throw<string> =
  if n > 2 then Throw.throw $"too big: {n}" else n * 10

let work (n: int) =
  use a = { name = "a" }
  let x = step n
  use b = { name = "b" }
  let y = step (n + 1)
  x + y

// a use in each round of a loop, and one around the loop
let rounds (stopAt: int) =
  use outer = { name = "outer" }
  let mutable total = 0
  for i in 1 .. 3 do
    use r = { name = $"r{i}" }
    if i = stopAt then Throw.throw $"stopped at {i}"
    total <- total + i
  total

// a handler inside the scope: the throw never passes the use
let caught () =
  use r = { name = "kept" }
  let inner = Throw.catch (fun () -> step 5)
  println $"  inside: {inner}"
  1

// an effect of the program's own, with a clause that stops
effect Abort =
  abstract abort : string -> 'a

let risky (n: int) =
  use r = { name = "risky" }
  if n < 0 then Abort.abort "negative"
  n * 2

// a clause that resumes: the rest runs, and disposes at the end, once
effect Emit =
  abstract emit : int -> unit

let emitting () =
  use r = { name = "emitter" }
  Emit.emit 1
  Emit.emit 2
  0

// a use in a local function the stop passes through, then the caller's
let nested () =
  use top = { name = "top" }
  let inner () =
    use deep = { name = "deep" }
    step 9
  inner () + 1

let main () =
  println $"{Throw.catch (fun () -> work 1)}"
  println $"{Throw.catch (fun () -> work 2)}"
  println $"{Throw.catch (fun () -> work 3)}"
  println $"{Throw.catch (fun () -> rounds 0)}"
  println $"{Throw.catch (fun () -> rounds 2)}"
  println $"{Throw.catch (fun () -> caught ())}"
  let aborted (n: int) =
    handle risky n with
    | Abort.abort msg, _ ->
      println $"  aborted: {msg}"
      -1
  println $"{aborted 4} {aborted (-4)}"
  let emitted =
    handle emitting () with
    | Emit.emit v, k ->
      println $"  emit {v}"
      v :: k ()
    | return r -> [ r ]
  println $"{emitted}"
  println $"{Throw.catch (fun () -> nested ())}"
  0
