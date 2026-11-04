/// UDP for tasks: a socket bound to a port, datagrams sent to a host and port and received with
/// their sender; and `Dns`, name lookup off the event loop's thread. A call that would block
/// waits for the event loop instead, so other tasks go on meanwhile.
namespace Net

/// A UDP socket (`Udp.bind`); `use` closes it.
type UdpSocket =
  /// The socket's file descriptor.
  | UdpSocket of int

/// `use` closes the socket.
impl Dispose<UdpSocket> =
  let dispose (UdpSocket fd) = Native.fdClose fd

/// Functions on UDP sockets.
module Udp =
  // what the runtime's calls give when they would block: wait, then try again
  let private wouldBlock = -1000

  /// A socket bound to the host (a name or an address; "" for every interface) and port (0 for
  /// one the system picks: `Udp.port` says which).
  let bind (host: string) (port: int) : result<UdpSocket, string> =
    let fd = Native.udpBind host port
    if fd < 0 then Error (Native.errorText fd) else Ok (UdpSocket fd)

  /// The port the socket is bound to.
  let port (s: UdpSocket) : int =
    let (UdpSocket fd) = s
    Native.socketPort fd

  /// Sends the buffer's first `n` bytes as one datagram to the host and port, waiting while the
  /// socket can't take it.
  let rec send (s: UdpSocket) (host: string) (port: int) (buf: Buffer<u8>) (n: int) : Task<result<unit, string>> =
    let (UdpSocket fd) = s

    task {
      let w = Native.udpSend fd host port buf n
      if w = wouldBlock then
        do! Task.waitFor fd true
        return! send s host port buf n
      else if w < 0 then
        return Error (Native.errorText w)
      else
        return Ok ()
    }

  /// Sends the text's bytes as one datagram.
  let sendText (s: UdpSocket) (host: string) (port: int) (text: string) : Task<result<unit, string>> =
    let buf = Buffer.ofSpan (String.bytes text)
    send s host port buf (Buffer.length buf)

  /// Waits for a datagram into the buffer: the bytes received (a longer datagram is cut to the
  /// buffer), and the sender's address and port.
  let rec receive (s: UdpSocket) (buf: Buffer<u8>) : Task<result<int * string * int, string>> =
    let (UdpSocket fd) = s

    task {
      let n = Native.udpReceive fd buf
      if n = wouldBlock then
        do! Task.waitFor fd false
        return! receive s buf
      else if n < 0 then
        return Error (Native.errorText n)
      else
        return Ok (n, Native.udpFrom (), Native.udpFromPort ())
    }

/// Name lookup.
module Dns =
  /// The addresses of a host (IPv4 and IPv6, as text, each once), looked up off the event loop's
  /// thread (`Task.blocking`) so other tasks go on meanwhile; an empty list for a name that has
  /// none.
  let lookup (host: string) : Task<list<string>> =
    task {
      let! text = Task.blocking (fun () -> Native.dnsLookup host)
      return List.filter (fun (a: string) -> a <> "") (String.splitLines text)
    }
