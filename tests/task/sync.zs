// A wait on a task whose work gives its result before returning (Task.complete inside work, as
// Task.wait on a fulfilled promise does): the state machine is resumed from inside the call, so
// the wait must not use anything of its own after it. In a loop, 1000 such waits leak nothing.
let now (v: ref<int>) : Task<int> = { ready = None; work = fun c k -> Task.complete k v.Value }

let inWhile (v: ref<int>) (n: int) =
  task {
    let mutable acc = 0
    let mutable i = 0
    while i < n do
      let! x = now v
      acc <- acc + x
      i <- i + 1
    return acc
  }

let inFor (v: ref<int>) (n: int) =
  task {
    let mutable acc = 0
    for i in 1 .. n do
      let! x = now v
      acc <- acc + x
    return acc
  }

let onPromise (p: Promise<int>) (n: int) =
  task {
    let mutable acc = 0
    let mutable i = 0
    while i < n do
      let! x = Task.wait p
      acc <- acc + x
      i <- i + 1
    return acc
  }

let main () =
  let v = ref 1
  println $"while {Task.run (inWhile v 1000)}"
  println $"for {Task.run (inFor v 1000)}"
  let p = Task.promise ()
  Task.fulfill p 1
  println $"promise {Task.run (onPromise p 1000)}"
  0
