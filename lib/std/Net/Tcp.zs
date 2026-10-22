/// TCP connections for tasks: listening, accepting, connecting, reading and writing. A call
/// that would block waits for the event loop instead, so other tasks go on meanwhile.
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

/// Functions on TCP sockets.
module Tcp =
  // what the runtime's calls give when they would block: wait, then try again
  let private wouldBlock = -1000

  /// A socket listening on the host (a name or an address; "" for every interface) and port.
  let listen (host: string) (port: int) : result<TcpListener, string> =
    let fd = Native.tcpListen host port
    if fd < 0 then Error (Native.errorText fd) else Ok (TcpListener fd)

  /// Waits for the next connection.
  let rec accept (l: TcpListener) : Task<result<TcpStream, string>> =
    let (TcpListener fd) = l

    task {
      let c = Native.tcpAccept fd
      if c = wouldBlock then
        do! Task.waitFor fd false
        return! accept l
      else if c < 0 then
        return Error (Native.errorText c)
      else
        return Ok (TcpStream c)
    }

  /// A connection to the host and port.
  let connect (host: string) (port: int) : Task<result<TcpStream, string>> =
    task {
      let fd = Native.tcpConnect host port
      if fd < 0 then
        return Error (Native.errorText fd)
      else
        do! Task.waitFor fd true
        let e = Native.socketError fd
        if e <> 0 then
          Native.fdClose fd
          return Error (Native.errorText e)
        else
          return Ok (TcpStream fd)
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
