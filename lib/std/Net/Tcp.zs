/// TCP connections for tasks: listening, accepting, connecting, reading and writing. A call
/// that would block waits for the event loop instead, so other tasks go on meanwhile, and the
/// name `Tcp.connect` is given is looked up off the loop's thread (`Tcp.listen` looks its own
/// up where it's called, before it gives the listener).
namespace Net

/// A socket listening for connections (`Tcp.listen`); `use` closes it.
type TcpListener =
  /// The socket's file descriptor.
  | TcpListener of int

/// A connection (`Tcp.accept`, `Tcp.connect`); `use` closes it.
type TcpStream =
  /// The socket's file descriptor.
  | TcpStream of int

/// `use` closes the listening socket.
impl Dispose<TcpListener> =
  let dispose (TcpListener fd) = Native.fdClose fd

/// `use` closes the connection.
impl Dispose<TcpStream> =
  let dispose (TcpStream fd) = Native.fdClose fd

// waits until the descriptor can be read (or, with write, written), and closes it if the task
// is cancelled first: one only this task has (a connection being made, a lookup's answer)
let private waitOrClose (fd: int) (write: bool) : Task<unit> =
  Task.fromCallback (fun k -> Native.loopWait fd write k) (fun () -> Native.fdClose fd)

// a lookup's answer, read to its end (where the lookup's thread closed it), and the descriptor
// closed
let rec private lookupAnswer (fd: int) (buf: Buffer<u8>) (got: string) : Task<result<string, string>> =
  task {
    let n = Native.fdRead fd buf 0 (Buffer.length buf)
    if n = -1000 then
      do! waitOrClose fd false
      return! lookupAnswer fd buf got
    else if n > 0 then
      return! lookupAnswer fd buf (got + String.ofBytes buf.[0 .. n - 1])
    else if n < 0 then
      Native.fdClose fd
      return Error (Native.errorText n)
    else
      Native.fdClose fd
      return Ok got
  }

// the addresses to connect or send to for host, in the order to try them: the host itself when
// it's an address already (or "", this machine), else what a thread of the runtime's own looks
// up while the loop goes on (the task waits for its answer: the addresses one per line, or "!"
// and why there are none)
let private addressesOf (host: string) : Task<result<list<string>, string>> =
  task {
    let fd = Native.dnsStart host
    if fd = -1001 then
      return Ok [ host ]
    else if fd < 0 then
      return Error (Native.errorText fd)
    else
      let! answer = lookupAnswer fd (Buffer.create 256 (u8 0)) ""
      match answer with
      | Error e -> return Error e
      | Ok text ->
        if String.startsWith "!" text then
          return Error (String.sub text 1 (String.length text - 1))
        else
          return Ok (String.splitLines text)
  }

/// Functions on TCP sockets.
module Tcp =
  // what the runtime's calls give when they would block: wait, then try again
  let private wouldBlock = -1000

  /// A socket listening on the host (a name or an address; "" for every interface) and port.
  let listen (host: string) (port: int) : result<TcpListener, string> =
    let fd = Native.tcpListen host port
    if fd < 0 then Error (Native.errorText fd) else Ok (TcpListener fd)

  /// Waits for the next connection. When taking it fails (the process is out of descriptors,
  /// say), the error comes after a pause of 100 ms, so a server that goes on accepting after
  /// one doesn't spin, and its other tasks get to close what they hold.
  let rec accept (l: TcpListener) : Task<result<TcpStream, string>> =
    let (TcpListener fd) = l

    task {
      let c = Native.tcpAccept fd
      if c = wouldBlock then
        do! Task.waitFor fd false
        return! accept l
      else if c < 0 then
        do! Task.sleep 100
        return Error (Native.errorText c)
      else
        return Ok (TcpStream c)
    }

  // a connection to an address being made, once it's made; the socket is closed when it fails,
  // or when the task is cancelled first
  let private attempt (address: string) (port: int) : Task<result<TcpStream, string>> =
    task {
      let fd = Native.tcpConnect address port
      if fd < 0 then
        return Error (Native.errorText fd)
      else
        do! waitOrClose fd true
        let e = Native.socketError fd
        if e <> 0 then
          Native.fdClose fd
          return Error (Native.errorText e)
        else
          return Ok (TcpStream fd)
    }

  // each address in turn until one connects: its connection, or the last one's error
  let rec private attemptEach (addresses: list<string>) (port: int) (lastError: string) : Task<result<TcpStream, string>> =
    task {
      match addresses with
      | [] -> return Error lastError
      | a :: rest ->
        let! got = attempt a port
        match got with
        | Ok _ -> return got
        | Error e -> return! attemptEach rest port e
    }

  /// A connection to the host and port: a name is looked up off the loop's thread, and its
  /// addresses tried in turn until one connects. Cancelled (by `Task.timeout`, say) before it
  /// has connected, it closes the socket it was connecting.
  let connect (host: string) (port: int) : Task<result<TcpStream, string>> =
    task {
      let! found = addressesOf host
      match found with
      | Error e -> return Error e
      | Ok addresses -> return! attemptEach addresses port "the host has no address"
    }

  /// Reads what has come into the buffer, waiting until something has: the number of bytes
  /// read, 0 once the other end has closed the connection.
  let rec read (s: TcpStream) (buf: Buffer<u8>) : Task<result<int, string>> =
    let (TcpStream fd) = s

    task {
      let n = Native.fdRead fd buf 0 (Buffer.length buf)
      if n = wouldBlock then
        do! Task.waitFor fd false
        return! read s buf
      else if n < 0 then
        return Error (Native.errorText n)
      else
        return Ok n
    }

  /// Writes the buffer's first `n` bytes, waiting while the connection can't take more.
  let write (s: TcpStream) (buf: Buffer<u8>) (n: int) : Task<result<unit, string>> =
    let (TcpStream fd) = s

    let rec from (off: int) =
      task {
        if off >= n then
          return Ok ()
        else
          let w = Native.fdWrite fd buf off (n - off)
          if w = wouldBlock then
            do! Task.waitFor fd true
            return! from off
          else if w < 0 then
            return Error (Native.errorText w)
          else
            return! from (off + w)
      }

    from 0

  /// Writes the text's bytes, waiting while the connection can't take more.
  let writeText (s: TcpStream) (text: string) : Task<result<unit, string>> =
    let (TcpStream fd) = s
    let n = String.length text

    let rec from (off: int) =
      task {
        if off >= n then
          return Ok ()
        else
          let w = Native.fdWriteText fd text off (n - off)
          if w = wouldBlock then
            do! Task.waitFor fd true
            return! from off
          else if w < 0 then
            return Error (Native.errorText w)
          else
            return! from (off + w)
      }

    from 0
