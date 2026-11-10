// What a task's body can't perform: an effect whose operation never resumes (no handler is on
// the stack to stop at when a task runs), and any effect where nothing can handle it (main)
effect Log =
  abstract note : string -> unit

let parse (s: string) : int / Throw<string> =
  match Int.parse s with
  | Some n -> n
  | None -> Throw.throw $"not a number: {s}"

let read (s: string) =
  task {
    do! Task.sleep 1
    return parse s
  }

let main () =
  let t =
    task {
      Log.note "unhandled"
      return 1
    }
  println $"{Task.run t}"
