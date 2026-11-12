// packages/tls (0032): a client and a server of this program's own over a loopback socket, with
// a certificate made as the test starts (no key is checked in). What's said both ways, a megabyte
// echoed, the end of a connection noticed, and what a client refuses: a certificate for another
// name, one it wasn't told to trust, and a server that isn't speaking TLS.
open Tls

let portOf (l: TcpListener) =
  let (TcpListener fd) = l
  Udp.port (UdpSocket fd)

// reads until `want` bytes have come or the peer is done: how many came, and their sum
let rec readAll (s: TlsStream) (buf: Buffer<u8>) (want: int) (got: int) (sum: int) : Task<result<int * int, Error>> =
  task {
    if got >= want then
      return Ok (got, sum)
    else
      let! r = Tls.read s buf
      match r with
      | Ok 0 -> return Ok (got, sum)
      | Ok n ->
        let mutable total = sum
        for i in 0 .. n - 1 do
          total <- (total + int buf.[i]) % 1000003
        return! readAll s buf want (got + n) total
      | Error e -> return Error e
  }

// the server's side of one connection: a greeting answered, then everything echoed until the
// client says it's done
let rec echo (s: TlsStream) (buf: Buffer<u8>) : Task<string> =
  task {
    let! r = Tls.read s buf
    match r with
    | Ok 0 -> return "the client closed"
    | Ok n ->
      let! w = Tls.write s buf n
      match w with
      | Ok () -> return! echo s buf
      | Error e -> return Error.message e
    | Error e -> return Error.message e
  }

let serveOne (config: ServerConfig) (l: TcpListener) : Task<string> =
  task {
    let! accepted = Tcp.accept l
    match accepted with
    | Error e -> return e
    | Ok stream ->
      let! secured = Tls.accept config stream
      match secured with
      | Error _ -> return "handshake refused"
      | Ok made ->
        use s = made
        return! echo s (Buffer.create 4096 (u8 0))
  }

// a client's conversation: what it learned
let talk (config: ClientConfig) (host: string) (port: int) : Task<string> =
  task {
    let! connected = Tcp.connect "127.0.0.1" port
    match connected with
    | Error e -> return e
    | Ok stream ->
      let! secured = Tls.connect config host stream
      match secured with
      | Error (Failed (_, m)) -> return $"refused: {m}"
      | Error e -> return $"refused: {Error.message e}"
      | Ok made ->
        use s = made
        let! _ = Tls.writeText s "hello over TLS"
        let small = Buffer.create 64 (u8 0)
        let! greeting = readAll s small 14 0 0
        let size = 1048576
        let big = Buffer.create size (u8 0)
        for i in 0 .. size - 1 do
          big.[i] <- u8 (i % 251)
        let mutable sum = 0
        for i in 0 .. size - 1 do
          sum <- (sum + i % 251) % 1000003
        let! sent = Tls.write s big size
        let! back = readAll s (Buffer.create 30000 (u8 0)) size 0 0
        let echoed =
          match sent, back with
          | Ok (), Ok (n, total) -> $"{n} bytes echoed, the same: {total = sum}"
          | Error e, _ -> Error.message e
          | _, Error e -> Error.message e
        let first =
          match greeting with
          | Ok (n, _) -> $"{n} bytes: {String.ofBytes small.[0 .. n - 1]}"
          | Error e -> Error.message e
        let! _ = Tls.close s
        let! after = Tls.read s small
        let closed =
          match after with
          | Error Closed -> "closed"
          | _ -> "still open"
        return $"{first}; {echoed}; then {closed}"
  }

// a server that answers in plain text
let plain (l: TcpListener) : Task<string> =
  task {
    let! accepted = Tcp.accept l
    match accepted with
    | Error e -> return e
    | Ok stream ->
      use s = stream
      let! _ = Tcp.writeText s "HTTP/1.1 400 Bad Request\r\n\r\n"
      return "answered in plain text"
  }

// whether it was made, or why not (Mbed TLS's message, without its code)
let show (r: result<'a, Error>) : string =
  match r with
  | Ok _ -> "ok"
  | Error (Failed (_, m)) -> m
  | Error e -> Error.message e

let run () : result<unit, Error> =
  let (certificate, key) = Tls.Config.selfSigned "localhost"?
  let (other, _) = Tls.Config.selfSigned "localhost"?
  let pem =
    String.startsWith "-----BEGIN CERTIFICATE-----" certificate && String.contains "PRIVATE KEY-----" key
  println $"a certificate and a key as PEM: {pem}"
  let made = Tls.Config.server certificate key?
  use server = made
  let trusting = Tls.Config.clientTrusting certificate?
  use client = trusting
  let stranger = Tls.Config.clientTrusting other?
  use elsewhere = stranger
  match Tcp.listen "127.0.0.1" 0 with
  | Error e -> println e
  | Ok listener ->
    use l = listener
    let port = portOf l
    let both (serving: Task<string>) (asking: Task<string>) =
      let (a, b) = Task.run (Task.both serving asking)
      println $"client: {b}"
      println $"server: {a}"
    both (serveOne server l) (talk client "localhost" port)
    println "== a certificate for another name"
    both (serveOne server l) (talk client "example.org" port)
    println "== a certificate the client wasn't told to trust"
    both (serveOne server l) (talk elsewhere "localhost" port)
    println "== a server that isn't speaking TLS"
    // what the client is told differs by system (a record that isn't one, or a reset)
    let (said, refused) = Task.run (Task.both (plain l) (talk client "localhost" port))
    println $"client: refused: {String.startsWith "refused: " refused}"
    println $"server: {said}"
  println "== what isn't a configuration"
  println (show (Tls.Config.server "not a certificate" key))
  println (show (Tls.Config.server certificate "not a key"))
  println (show (Tls.Config.clientTrusting ""))
  println (show (Tls.Config.selfSigned "two words"))
  println (show (Tls.Config.ofFiles "/nonexistent/cert.pem" "/nonexistent/key.pem"))
  match Tls.Config.client () with
  | Ok system ->
    dispose system
    println "the system's authorities: ok"
  | Error e -> println $"the system's authorities: {Error.message e}"
  Ok ()

let main () =
  match run () with
  | Ok () -> 0
  | Error e ->
    println $"failed: {Error.message e}"
    1
