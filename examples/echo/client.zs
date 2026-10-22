// A load for the echo server (phase 6's exit test): opens `connections` connections, and on each,
// every `interval` ms for `seconds`, writes a line and checks that the same bytes come back.
// Prints the round trips and failures; with "quit", stops the server after.
// Usage: client [port] [connections] [seconds] [interval ms] [quit]
let rec arg (args: list<string>) (i: int) (d: int) =
  match (args, i) with
  | a :: _, 0 -> Option.defaultValue d (String.parseInt a)
  | _ :: rest, _ -> arg rest (i - 1) d
  | [], _ -> d

// whether the n bytes read match the message from byte `at`
let same (buf: Buffer<u8>) (n: int) (msg: string) (at: int) =
  let mutable ok = at + n <= String.length msg
  let mutable i = 0
  while ok && i < n do
    ok <- buf.[i] = String.byte msg (at + i)
    i <- i + 1
  ok

// reads until the whole message has come back
let rec expect (c: TcpStream) (buf: Buffer<u8>) (msg: string) (at: int) : Task<bool> =
  task {
    if at >= String.length msg then
      return true
    else
      let! r = Tcp.read c buf
      match r with
      | Ok n when n > 0 && same buf n msg at -> return! expect c buf msg (at + n)
      | _ -> return false
  }

let rec talk (c: TcpStream) (buf: Buffer<u8>) (msg: string) (until: u64) (interval: int) (trips: ref<int>) : Task<bool> =
  task {
    if Runtime.ticks () >= until then
      return true
    else
      let! w = Tcp.writeText c msg
      let! ok = expect c buf msg 0
      if ok && Result.isOk w then
        trips.Value <- trips.Value + 1
        do! Task.sleep interval
        return! talk c buf msg until interval trips
      else
        return false
  }

let connection (port: int) (i: int) (until: u64) (interval: int) (trips: ref<int>) : Task<bool> =
  task {
    // not all at once: the server's backlog takes a few thousand
    do! Task.sleep (i / 20)
    let! r = Tcp.connect "127.0.0.1" port
    match r with
    | Error e ->
      eprintln $"connect {i}: {e}"
      return false
    | Ok conn ->
      use c = conn
      return! talk c (Buffer.create 64 (u8 0)) $"connection {i} says hello\n" until interval trips
  }

let main () =
  let args = Environment.args ()
  let port = arg args 0 9900
  let n = arg args 1 100
  let seconds = arg args 2 2
  let interval = arg args 3 1000
  let until = Runtime.ticks () + u64 seconds * u64 1000000000
  let trips = ref 0
  let results = Task.run (Task.all (List.init n (fun i -> connection port i until interval trips)))
  let failed = results |> List.filter (fun ok -> not ok) |> List.length
  println $"{n} connections, {trips.Value} round trips, {failed} failed"

  if List.contains "quit" args then
    Task.run (
      task {
        let! r = Tcp.connect "127.0.0.1" port
        match r with
        | Ok conn ->
          use c = conn
          let! _ = Tcp.writeText c "quit"
          return ()
        | Error e -> eprintln $"quit: {e}"
      }
    )

  if failed = 0 then 0 else 1
