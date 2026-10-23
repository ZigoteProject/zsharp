/// Unix sockets for tasks: `Tcp`'s calls over a path in the file system instead of a host and
/// a port, for processes on one machine (the build server's socket). A listener and a connection
/// are `Tcp`'s types, so `Tcp.read`, `Tcp.write` and `use` work on them as they are.
namespace Net

/// Functions on Unix sockets.
module Unix =
  /// A socket listening at `path`; a socket file left there by an earlier run is removed first.
  let listen (path: string) : result<TcpListener, string> =
    let fd = Native.unixListen path
    if fd < 0 then Error (Native.errorText fd) else Ok (TcpListener fd)

  /// Waits for the next connection: `Tcp.accept`, which takes a Unix listener too.
  let accept (l: TcpListener) : Task<result<TcpStream, string>> = Tcp.accept l

  /// A connection to the socket at `path`.
  let connect (path: string) : Task<result<TcpStream, string>> =
    task {
      let fd = Native.unixConnect path
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
