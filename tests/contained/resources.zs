// what the runtime did for a contained job is undone when the job fails (0035): the descriptors
// it opened are closed, its weak references forgotten, its handlers gone, and the work it
// started on other threads is no longer waited for. Arenas and jobs nest either way.
open Threading
open IO

effect Log =
  abstract note : string -> unit

let noisy (n: int) : int / Log =
  Log.note $"n is {n}"
  if n > 2 then panic "too big" else n

// the lines noted while f ran, and its result
let logged (f: unit -> int / <Log | 'e>) : string / 'e =
  let lines = ref []
  let r =
    handle f () with
    | Log.note s, k ->
      lines.Value <- s :: lines.Value
      k ()
  $"{r} after {List.rev lines.Value}"

// the number the system gives the next descriptor opened
let nextDescriptor (path: string) : int =
  match File.openRead path with
  | Ok r ->
    use reader = r
    reader.fd
  | Error _ -> -1

// closes a descriptor a job returned
let close (fd: int) =
  use reader = Reader.ofFd fd
  ()

let slowly (n: int) : Task<int> =
  task {
    do! Task.sleep 30
    return n
  }

let main () =
  let path = Result.defaultValue "" (File.createTemp "contained")
  File.writeAllText path "some text\n" |> ignore
  // a hundred jobs open the file and fail without closing it
  let before = nextDescriptor path
  let mutable opened = 0
  for _ in 1 .. 100 do
    match Contained.run (fun () ->
      match File.openRead path with
      | Ok r -> if r.fd >= 0 then panic "holding a file" else 0
      | Error _ -> 1) with
    | Ok _ -> ()
    | Error _ -> opened <- opened + 1
  println $"{opened} jobs failed holding the file; descriptors left open: {nextDescriptor path - before}"
  // one that returns its reader: still open, the caller's to close
  match Contained.run (fun () -> Result.map (fun (r: Reader) -> r.fd) (File.openRead path)) with
  | Ok(Ok fd) ->
    println $"returned open: {fd = before}"
    close fd
  | _ -> println "not opened"
  File.delete path |> ignore

  // weak references in a job: to its own objects and to its caller's
  let table = [ "the"; "caller's" ]
  let mine = Weak.create table
  let inJob =
    Contained.run (fun () ->
      let own = [ "made"; "in"; "the"; "job" ]
      let w = Weak.create own
      let w2 = Weak.create table
      (Option.map List.length (Weak.get w), Option.map List.length (Weak.get w2)))
  println $"{inJob} {Option.map List.length (Weak.get mine)}"
  let failing =
    Contained.run (fun () ->
      let w = Weak.create table
      let own = Weak.create [ 1; 2; 3 ]
      if Option.isSome (Weak.get w) then
        panic "holding weak references"
      else
        Option.isSome (Weak.get own))
  println $"{failing} {Option.map List.length (Weak.get mine)} {Option.map List.length (Weak.get (Weak.create table))}"

  // handlers installed in a job: gone with it when a panic passes them
  println $"{Contained.run (fun () -> logged (fun () -> noisy 1 + noisy 2))}"
  println $"{Contained.run (fun () -> logged (fun () -> noisy 1 + noisy 5))}"
  println $"{logged (fun () -> noisy 2)}"

  // an arena around a job and in one
  let around =
    Arena.with (fun () -> Contained.run (fun () -> List.sum (List.init 1000 (fun i -> i))))
  let within =
    Contained.run (fun () -> Arena.with (fun () -> List.length (List.init 1000 (fun i -> $"{i}"))))
  let failed =
    Contained.run (fun () ->
      Arena.with (fun () -> if List.length table = 2 then panic "in an arena" else 0))
  println $"{around} {within} {failed}"

  // a task's job that fails while a helper thread and another loop's task work for it: their
  // results come back to no one, and the loop goes on
  let hasty =
    Task.run (
      Contained.task (fun () ->
        task {
          let! (a, b) =
            Task.both (Task.both (Task.blocking (fun () -> List.init 100 (fun i -> $"{i}"))) (Task.spawn (fun () -> slowly 5))) (task {
                do! Task.sleep 1
                return (if List.length table = 2 then panic "not waiting" else 0)
              })
          return b
        }))
  println $"{hasty}"
  // and one that waits for them
  let patient =
    Task.run (
      Contained.task (fun () ->
        task {
          let! (words, n) =
            Task.both (Task.blocking (fun () -> List.init 100 (fun i -> $"{i}"))) (Task.spawn (fun () ->
                slowly 5))
          return List.length words + n
        }))
  println $"{patient}"
