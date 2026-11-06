// Tcp.connect: a name looked up off the loop's thread, and each of its addresses tried in turn
// ("localhost" may be ::1 first, and the listener is on 127.0.0.1 alone); a name with no
// address an error; connects cancelled while they wait (Task.timeout) leave no socket open; a
// port past 65535 an error, not its low 16 bits (glibc's 65561 is 25)
let portOf (l: TcpListener) =
  let (TcpListener fd) = l
  Udp.port (UdpSocket fd)

// the descriptor a new socket gets: the lowest free one (on Windows the slot freed last), so one
// left open in between shows as another
let nextDescriptor () =
  match Udp.bind "127.0.0.1" 0 with
  | Ok s ->
    use probe = s
    let (UdpSocket fd) = probe
    fd
  | Error e -> panic $"bind: {e}"

let main () =
  match Tcp.listen "127.0.0.1" 0 with
  | Error e ->
    println $"listen: {e}"
    1
  | Ok listener ->
    use l = listener
    let port = portOf l
    let local =
      Task.run (task {
          let! c = Tcp.connect "localhost" port
          match c with
          | Ok conn ->
            use s = conn
            return "connected"
          | Error e -> return e
        })
    println $"localhost: {local}"
    println $"no.such.host.invalid: {Result.isError (Task.run (Tcp.connect "no.such.host.invalid" port))}"
    let before = nextDescriptor ()
    for _ in 1 .. 100 do
      Task.run (Task.timeout 0 (Tcp.connect "127.0.0.1" port)) |> ignore
    println $"100 connects cancelled, none left open: {nextDescriptor () = before}"
    let listening = Result.isError (Tcp.listen "127.0.0.1" 65536)
    let connecting = Result.isError (Task.run (Tcp.connect "127.0.0.1" 65561))
    let bound = Result.isError (Udp.bind "127.0.0.1" (-1))
    println $"ports out of range are errors: {listening && connecting && bound}"
    0
