// The guide's accept loop (docs/guide/13-tasks.md), for tests/task/emfile.sh, which runs it with
// few descriptors: a failed accept is counted and the loop goes on; each connection is read until
// its client closes it, and one sending "quit" stops the server. Usage: emfile port
let rec serve (c: TcpStream) (buf: Buffer<u8>) (quit: Promise<unit>) : Task<unit> =
  task {
    let! r = Tcp.read c buf
    match r with
    | Ok n when n > 0 && buf.[0] = u8 'q' ->
      Task.fulfill quit ()
      return ()
    | Ok n when n > 0 -> return! serve c buf quit
    | _ -> return ()
  }

let rec accepting (l: TcpListener) (s: Scope) (quit: Promise<unit>) (failed: ref<int>) : Task<unit> =
  task {
    let! r = Tcp.accept l
    match r with
    | Ok conn ->
      Task.start s (task {
          use c = conn
          return! serve c (Buffer.create 64 (u8 0)) quit
        }) |> ignore
    | Error _ -> failed.Value <- failed.Value + 1
    return! accepting l s quit failed
  }

let main () =
  let port =
    match Environment.args () with
    | p :: _ -> Option.defaultValue 0 (String.parseInt p)
    | [] -> 0
  match Tcp.listen "127.0.0.1" port with
  | Error e ->
    eprintln $"listen: {e}"
    1
  | Ok listener ->
    let quit = Task.promise ()
    let failed = ref 0
    Task.run (
      Task.scope (fun s ->
        task {
          use l = listener
          let! _ = Task.race (accepting l s quit failed) (Task.wait quit)
          Task.cancel s
        })
    )
    // a few: a pause after each, rather than millions
    println $"stopped; accepts that failed, a few: {failed.Value > 0 && failed.Value < 100}"
    0
