// Effect handlers: state, collecting, nested handlers, resumptions kept for later, clauses
// performing outer effects, effect-polymorphic library functions (phase 10)

effect Gen<'a> =
  abstract gen : 'a -> unit

effect State<'s> =
  abstract get : unit -> 's
  abstract put : 's -> unit

effect Ask =
  abstract ask : unit -> int

effect Store =
  abstract set : string -> int -> unit

let numbers n =
  for i in 1 .. n do Gen.gen i

// a clause that uses what the rest gives back: x :: k ()
let collect n =
  handle numbers n with
  | Gen.gen x, k -> x :: k ()
  | return () -> []

let take n f =
  let count = ref 0
  handle f () with
  | Gen.gen x, k ->
    if count.Value < n then
      count.Value <- count.Value + 1
      x :: k ()
    else []
  | return () -> []

// mutable variables live across the yields of a while loop
let evens n =
  let mutable i = 0
  let mutable sent = 0
  while i < n do
    if i % 2 = 0 then
      Gen.gen i
      sent <- sent + 1
    i <- i + 1
  Gen.gen (100 + sent)

let counter () =
  let s = State.get ()
  State.put (s + 1)
  let t = State.get ()
  State.put (t * 10)
  t

// a clause may assign the mutable variables of the function the handle is in
let runState init f =
  let mutable st = init
  let r =
    handle f () with
    | State.get (), k -> k st
    | State.put v, k ->
      st <- v
      k ()
  (r, st)

// List.iter is polymorphic in its function's effects: it yields here
let doubledSum xs =
  let total = ref 0
  handle List.iter (fun x -> Gen.gen (x * 2)) xs with
  | Gen.gen x, k ->
    total.Value <- total.Value + x
    k ()
  | return () -> total.Value

// a clause performing its own effect goes to the next handler out
let doubled f =
  handle f () with
  | Gen.gen x, k ->
    Gen.gen (x * 2)
    k ()

// two handlers of one effect: the innermost takes it
let nested () =
  handle
    handle Gen.gen 1 with
    | Gen.gen x, k -> k ()
    Gen.gen 2
  with
  | Gen.gen x, k -> x :: k ()
  | return () -> []

// resumptions kept and run later
let later () =
  let saved = ref []
  let out = ref []
  handle
    Gen.gen 1
    Gen.gen 2
    Gen.gen 3
  with
  | Gen.gen x, k ->
    out.Value <- x :: out.Value
    saved.Value <- k :: saved.Value
  | return () -> ()
  while not (List.isEmpty saved.Value) do
    let ks = saved.Value
    saved.Value <- []
    for k in ks do k ()
  List.rev out.Value

// a pure function where one that performs is expected
let one () = 1
let pick (b: bool) = if b then one else (fun () -> Ask.ask ())

let fill () =
  Store.set "a" 1
  Store.set "b" 2

type Tree =
  | Leaf
  | Node of Tree * int * Tree

let rec walk t =
  match t with
  | Leaf -> ()
  | Node(l, v, r) ->
    walk l
    Gen.gen v
    walk r

let rec build lo hi =
  if lo > hi then Leaf
  else
    let m = (lo + hi) / 2
    Node(build lo (m - 1), m, build (m + 1) hi)

let main () =
  println $"{collect 5}"
  println $"{take 3 (fun () -> evens 20)} {take 20 (fun () -> evens 7)}"
  println $"{runState 5 counter}"
  println $"{doubledSum [ 1; 2; 3; 4 ]}"
  println $"{take 10 (fun () -> doubled (fun () -> numbers 4))}"
  println $"{nested ()} {later ()}"
  let a = handle (pick true) () + (pick false) () with
    | Ask.ask (), k -> k 41
  println $"{a}"
  let mutable log = ""
  handle fill () with
  | Store.set key v, k ->
    log <- log + $"{key}={v};"
    k ()
  println log
  println $"{take 100 (fun () -> walk (build 1 10))}"
  // ten million rounds through a handler that resumes at once: no yield, no stack
  let mutable sum = 0
  handle numbers 10000000 with
  | Gen.gen x, k ->
    sum <- sum + x
    k ()
  println $"{sum}"
  0
