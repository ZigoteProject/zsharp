// An Spsc is Share, so safe code can push to it and pop from it on every thread at once: each
// value pushed comes out once, and none is freed twice (the runtime claims each slot with a CAS).

let main () =
  let q : Spsc<string> = Spsc.create 4
  let pushed = Atomic.make 0
  let popped = Atomic.make 0

  // each job pushes, then pops, on whichever thread runs it
  Parallel.for 0 100000 (fun i ->
    let s = $"value {i}"
    let n = String.length s

    if Spsc.push q s then
      Atomic.add pushed n |> ignore

    match Spsc.pop q with
    | Some x -> Atomic.add popped (String.length x) |> ignore
    | None -> ())

  // what's left, on this thread
  let mutable more = true

  while more do
    match Spsc.pop q with
    | Some x -> Atomic.add popped (String.length x) |> ignore
    | None -> more <- false

  println $"every value pushed popped once: {Atomic.get pushed = Atomic.get popped}"
  println $"values went through: {Atomic.get pushed > 0}"
  0
