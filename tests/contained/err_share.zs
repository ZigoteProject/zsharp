// a contained job's function is a share<…>, and its result must be Share (0035)
open Threading

let main () =
  // the result: a Buffer isn't Share
  let r = Contained.run (fun () -> Buffer.create 3 0)
  // what the function captures: a ref isn't Share
  let count = ref 0
  let r2 =
    Contained.run (fun () ->
      count.Value <- count.Value + 1
      count.Value)
  // a task's job, the same
  let t = Contained.task (fun () -> task { return ref 1 })
  println $"{Result.isOk r} {r2} {Result.isOk (Task.run t)}"
