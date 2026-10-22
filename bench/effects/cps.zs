// The phase 6 gate (DESIGN §6): n awaits as the CPS translation of task { } runs them. Each
// bind gives its continuation to the computation; an await either completes at once or
// suspends until the event loop (a queue here) resumes it.
type Async<'a> = Async of (('a -> unit) -> unit)

let start (Async f) (k: 'a -> unit) = f k

let ret (x: 'a) = Async(fun k -> k x)

let bind (m: Async<'a>) (f: 'a -> Async<'b>) = Async(fun k -> start m (fun x -> start (f x) k))

let await (queue: ref<list<unit -> unit>>) (suspend: bool) (x: int) : Async<int> =
  if suspend then Async(fun k -> queue.Value <- (fun () -> k x) :: queue.Value) else ret x

let rec loop queue suspend i n acc =
  if i > n then ret acc else bind (await queue suspend i) (fun x -> loop queue suspend (i + 1) n (acc + x))

let rec drain (queue: ref<list<unit -> unit>>) =
  match queue.Value with
  | [] -> ()
  | k :: rest ->
    queue.Value <- rest
    k ()
    drain queue

let measure (suspend: bool) (n: int) =
  let queue = ref []
  let result = ref 0
  let before = Runtime.allocations ()
  start (loop queue suspend 1 n 0) (fun r -> result.Value <- r)
  drain queue
  let per = float (Runtime.allocations () - before) / float n
  println $"cps, {if suspend then "suspending" else "completing at once"}: sum {result.Value}, {per} allocations per await"

let main () =
  // at once, each await's continuation runs inside the last: the stack grows with n
  measure false 10000
  measure true 1000000
  0
