// UDP for tasks (track S, item 8): two sockets on the loopback, a datagram each way with its
// sender's port, a datagram longer than the buffer cut to it, a port nothing listens on, and a
// name looked up off the loop's thread
let bound () =
  match Udp.bind "127.0.0.1" 0 with
  | Ok s -> s
  | Error e -> panic $"bind: {e}"

let text (buf: Buffer<u8>) (n: int) = String.ofBytes (Buffer.toArray buf).[0..n - 1]

// a port nothing listens on any more
let closed () =
  use s = bound ()
  Udp.port s

let main () =
  use a = bound ()
  use b = bound ()
  let pa = Udp.port a
  let pb = Udp.port b
  let buf = Buffer.create 16 (u8 0)
  let r =
    Task.run (task {
        let! sent = Udp.sendText a "127.0.0.1" pb "ping"
        let! got = Udp.receive b buf
        match (sent, got) with
        | (Ok (), Ok (n, from, port)) ->
          println $"b got {text buf n} from {from}, a's port {port = pa}"
        | (s, g) -> println $"ping: {s} {g}"
        let! _ = Udp.sendText b "127.0.0.1" pa "pong"
        let! back = Udp.receive a buf
        match back with
        | Ok (n, _, port) -> println $"a got {text buf n}, b's port {port = pb}"
        | Error e -> println $"pong: {e}"
        let! _ = Udp.sendText a "127.0.0.1" pb "0123456789abcdefXYZ"
        let! long = Udp.receive b buf
        match long with
        | Ok (n, _, _) -> println $"cut to {n} bytes: {text buf n}"
        | Error e -> println $"long: {e}"
        // the port unreachable it draws isn't a's next receive's failure (it was on Windows)
        let! _ = Udp.sendText a "127.0.0.1" (closed ()) "lost"
        let! _ = Udp.sendText b "127.0.0.1" pa "after"
        let! after = Udp.receive a buf
        match after with
        | Ok (n, _, _) -> println $"after a send to a closed port, a got {text buf n}"
        | Error e -> println $"after a send to a closed port: {e}"
        let! local = Dns.lookup "localhost"
        let! nowhere = Dns.lookup "no.such.host.invalid"
        println $"localhost is loopback: {List.contains "127.0.0.1" local || List.contains "::1" local}, nowhere: {nowhere}"
        return 0
      })
  r
