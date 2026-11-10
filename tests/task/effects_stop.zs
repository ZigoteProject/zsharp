// A handler that doesn't resume an operation a task performed: a panic that says so, where the
// task performs it (after its wait, when the handler has returned)
effect Ask =
  abstract ask : string -> int

let work () =
  task {
    do! Task.sleep 1
    return Ask.ask "x" + 1
  }

let main () =
  let t =
    handle work () with
    | Ask.ask _, _ -> Task.ret -1
  println "made"
  println $"{Task.run t}"
