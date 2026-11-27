// A server whose every connection is a contained job (0035): a bug in one connection's handling
// ends that one, which is answered with a failure, and the others, on the same loop, go on.
// The connection's socket is the server's, opened outside the job and closed there.

// the port the system gave the listening socket
let portOf (l: TcpListener) : int =
  let (TcpListener fd) = l
  Udp.port (UdpSocket fd)

// answers each word with it in capitals, until the client closes: how many it answered. "boom"
// finds the bug
let rec talk (c: TcpStream) (buf: Buffer<u8>) (served: int) : Task<int> =
  task {
    let! r = Tcp.read c buf
    match r with
    | Ok n when n > 0 ->
      let word = String.ofBytes buf.[0 .. n - 1]
      let history = List.init (served + 1) (fun i -> $"{word} {i}")
      if word = "boom" then
        panic $"a bug in the connection that had answered {List.length history - 1}"
      let! w = Tcp.writeText c (String.toUpper word)
      return! talk c buf (served + 1)
    | _ -> return served
  }

// a connection: its talk is a job; what it comes to is said here, outside it
let connection (conn: TcpStream) : Task<string> =
  task {
    use c = conn
    let! r = Contained.task (fun () -> talk c (Buffer.create 64 (u8 0)) 0)
    match r with
    | Ok n -> return $"answered {n}"
    | Error p ->
      let! w = Tcp.writeText c "500"
      return $"failed ({p.message})"
  }

let rec accepting (l: TcpListener) (left: int) (ended: list<Promise<string>>) (s: Scope) : Task<list<string>> =
  task {
    if left = 0 then
      let! all = Task.all (List.map Task.wait (List.rev ended))
      return all
    else
      let! r = Tcp.accept l
      match r with
      | Ok c -> return! accepting l (left - 1) (Task.start s (connection c) :: ended) s
      | Error e -> return [ e ]
  }

// a client: sends its words in turn, and gives the answers
let client (port: int) (words: list<string>) : Task<list<string>> =
  task {
    let! r = Tcp.connect "127.0.0.1" port
    match r with
    | Error e -> return [ e ]
    | Ok conn ->
      use c = conn
      let buf = Buffer.create 64 (u8 0)
      let answers = Buffer.empty
      for word in words do
        let! w = Tcp.writeText c word
        let! got = Tcp.read c buf
        match got with
        | Ok n -> Buffer.push (String.ofBytes buf.[0 .. n - 1]) answers
        | Error e -> Buffer.push e answers
      return Array.toList (Buffer.toArray answers)
  }

let main () =
  match Tcp.listen "127.0.0.1" 0 with
  | Error e ->
    println $"listen: {e}"
    1
  | Ok listener ->
    use l = listener
    let port = portOf l
    // eight clients, one after another so the order is the same every run; the third and the
    // sixth send the word that finds the bug, after two that don't
    let words (i: int) =
      if i % 3 = 2 then [ "one"; "two"; "boom" ] else [ $"hello{i}"; "again"; "bye" ]
    let rec clients (i: int) : Task<list<list<string>>> =
      task {
        if i = 8 then
          return []
        else
          let! answers = client port (words i)
          let! rest = clients (i + 1)
          return answers :: rest
      }
    let (served, answers) =
      Task.run (Task.scope (fun s -> Task.both (accepting l 8 [] s) (clients 0)))
    for a in answers do
      println $"client: {a}"
    for line in served do
      println $"server: {line}"
    0
