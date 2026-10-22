// A TCP echo server (phase 6's exit test): each connection is a task, which writes back what it
// reads until the client closes it. A connection that sends "quit" stops the server: it stops
// accepting, cancels the connections still open (each task's `use` closes its socket), and
// returns. Usage: server [port] (9900 by default).
let isQuit (buf: Buffer<u8>) (n: int) =
  n >= 4 && buf.[0] = u8 'q' && buf.[1] = u8 'u' && buf.[2] = u8 'i' && buf.[3] = u8 't'

let rec echo (c: TcpStream) (buf: Buffer<u8>) (quit: Promise<unit>) : Task<unit> =
  task {
    let! r = Tcp.read c buf
    match r with
    | Ok n when n > 0 ->
      if isQuit buf n then
        Task.fulfill quit ()
      else
        let! w = Tcp.write c buf n
        match w with
        | Ok () -> return! echo c buf quit
        | Error _ -> return ()
    | _ -> return ()
  }

let serve (conn: TcpStream) (quit: Promise<unit>) : Task<unit> =
  task {
    use c = conn
    return! echo c (Buffer.create 512 (u8 0)) quit
  }

let rec accepting (l: TcpListener) (s: Scope) (quit: Promise<unit>) : Task<unit> =
  task {
    let! r = Tcp.accept l
    match r with
    | Ok c -> Task.start s (serve c quit) |> ignore
    | Error e ->
      // out of descriptors, say: wait a moment rather than spin
      eprintln $"accept: {e}"
      do! Task.sleep 100
    return! accepting l s quit
  }

let main () =
  let port =
    match Environment.args () with
    | p :: _ -> Option.defaultValue 9900 (String.parseInt p)
    | [] -> 9900

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
          let! _ = Task.race (accepting l s quit) (Task.wait quit)
          Task.cancel s
        })
    )

    println "echo server stopped"
    0
