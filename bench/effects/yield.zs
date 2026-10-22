// The phase 6 gate (DESIGN §6): n awaits as evidence passing with yield bubbling compiles an
// Async effect (Xie & Leijen 2021, as Koka does). An operation that completes at once just
// returns. One that can't sets `yielding`; each caller on the way out adds the rest of its frame
// to the continuation and returns too, and the handler (the event loop) resumes the whole chain
// later. Here written by hand: the compiler would add the check after every call that may yield.
let await (yielding: ref<bool>) (queue: ref<list<unit -> unit>>) (suspend: bool) (x: int) : int =
  if suspend then
    yielding.Value <- true
    x
  else
    x

let rec loop yielding (k: ref<int -> unit>) queue suspend i n acc : unit =
  if i > n then
    k.Value acc
  else
    let x = await yielding queue suspend i

    if yielding.Value then
      // the rest of this frame, resumed by the handler with the operation's result
      yielding.Value <- false
      queue.Value <- (fun () -> loop yielding k queue suspend (i + 1) n (acc + x)) :: queue.Value
    else
      loop yielding k queue suspend (i + 1) n (acc + x)

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
  let yielding = ref false
  let k = ref (fun (r: int) -> result.Value <- r)
  let before = Runtime.allocations ()
  loop yielding k queue suspend 1 n 0
  drain queue
  let per = float (Runtime.allocations () - before) / float n
  println $"yield bubbling, {if suspend then "suspending" else "completing at once"}: sum {result.Value}, {per} allocations per await"

let main () =
  measure false 1000000
  measure true 1000000
  0
