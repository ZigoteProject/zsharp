// A `use` written inside a task's body, under a handle in the body that stops without resuming:
// disposed on the stop's way out, and off the task's Cancel, as a stop outside a task is; the
// scope's end still disposes when nothing stops
type Res = { name: string }

impl Dispose<Res> =
  let dispose (r: Res) = println $"  dispose {r.name}"

let step (n: int) : int / Throw<string> =
  if n > 2 then Throw.throw $"too big: {n}" else n * 10

let stopped () =
  task {
    let inner =
      Throw.catch (fun () ->
        use r = { name = "stopped" }
        step 5)
    return $"{inner}"
  }

let whole () =
  task {
    let inner =
      Throw.catch (fun () ->
        use r = { name = "whole" }
        step 1)
    return $"{inner}"
  }

let main () =
  println $"{Task.run (stopped ())}"
  println $"{Task.run (whole ())}"
  0
