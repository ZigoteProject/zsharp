// A resumption a clause kept and never called (track S, item 10): the `use` scopes of the frames
// it would have resumed are disposed when the resumption is dropped, the frames within first (as
// a stop's unwinding does), since nothing else will run them; one that is called disposes as its
// scopes end, once. A generator its consumer left mid-iteration is the case a program meets
type Res = { name: string }

impl Dispose<Res> =
  let dispose (r: Res) = println $"  dispose {r.name}"

effect Ask =
  abstract ask : int -> int

let work (n: int) : int =
  use r = { name = $"w{n}" }
  Ask.ask n

// a frame in a frame: the inner's scope is disposed first
let inner (n: int) : int =
  use r = { name = "inner" }
  Ask.ask (n + 1)

let outer () : int =
  use r = { name = "outer" }
  inner 5

// a generator with a use, its consumer keeping the resumption of the first yield
let numbers () =
  seq {
    use r = { name = "gen" }
    yield 1
    yield 2
  }

let main () =
  let stash : ref<option<int -> int>> = ref None
  let first =
    handle work 1 with
    | Ask.ask _, k ->
      stash.Value <- Some k
      -1
  println $"{first}"
  stash.Value <- None
  println "dropped"
  let stash2 : ref<option<int -> int>> = ref None
  let made =
    handle work 2 with
    | Ask.ask _, k ->
      stash2.Value <- Some k
      -1
  let finish () =
    match stash2.Value with
    | Some k -> k 0
    | None -> -2
  println $"{made} {finish ()}"
  stash2.Value <- None
  println "after"
  let stash3 : ref<option<int -> int>> = ref None
  let nested =
    handle outer () with
    | Ask.ask _, k ->
      stash3.Value <- Some k
      -1
  println $"{nested}"
  stash3.Value <- None
  println "gone"
  let genStash : ref<option<unit -> unit>> = ref None
  let (Seq body) = numbers ()
  handle body () with
  | Yield.yield _, k ->
    genStash.Value <- Some k
  | return _ -> ()
  println $"took {genStash.Value.IsSome}"
  genStash.Value <- None
  println "left"
  0
