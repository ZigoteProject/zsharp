// A TCP echo server (phase 6's exit test): each connection is a task, which writes back what it
// reads until the client closes it. A connection that sends "quit" stops the server: it stops
// accepting, cancels the connections still open (each task's `use` closes its socket), and
// returns. With --threads, each connection runs on another thread's event loop (Task.spawn),
// so the connections spread over every core. Usage: server [port] [--threads] (port 9900 by
// default).
let isQuit (buf: Buffer<u8>) (n: int) =
  n >= 4 && buf.[0] = u8 'q' && buf.[1] = u8 'u' && buf.[2] = u8 'i' && buf.[3] = u8 't'

// writes back what it reads, until the client closes it: true when it asked to quit
let rec echo (c: TcpStream) (buf: Buffer<u8>) : Task<bool> =
  task {
    let! r = Tcp.read c buf
    match r with
    | Ok n when n > 0 ->
      if isQuit buf n then
        return true
      else
        let! w = Tcp.write c buf n
        match w with
        | Ok () -> return! echo c buf
        | Error _ -> return false
    | _ -> return false
  }

let serve (conn: TcpStream) : Task<bool> =
  task {
    use c = conn
    return! echo c (Buffer.create 512 (u8 0))
  }

let rec accepting (l: TcpListener) (s: Scope) (quit: Promise<unit>) (spread: bool) : Task<unit> =
  task {
    let! r = Tcp.accept l
    match r with
    | Ok c ->
      let connection = if spread then Task.spawn (fun () -> serve c) else serve c
      Task.start s (task {
        let! q = connection
        if q then
          Task.fulfill quit ()
      }) |> ignore
    | Error e ->
      // out of descriptors, say: wait a moment rather than spin
      eprintln $"accept: {e}"
      do! Task.sleep 100
    return! accepting l s quit spread
  }

let main () =
  let args = Environment.args ()
  let port =
    match args with
    | p :: _ -> Option.defaultValue 9900 (String.parseInt p)
    | [] -> 9900
  let spread = List.contains "--threads" args

  match Tcp.listen "127.0.0.1" port with
  | Error e ->
    eprintln $"listen: {e}"
    1
  | Ok listener ->
    println $"echo server on port {port}"
    let quit = Task.promise ()

    Task.run (
      Task.scope (fun s ->
        task {
          use l = listener
          let! _ = Task.race (accepting l s quit spread) (Task.wait quit)
          Task.cancel s
        })
    )

    println "echo server stopped"
    0
