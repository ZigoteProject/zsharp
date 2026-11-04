# Net.Udp

UDP for tasks: a socket bound to a port, datagrams sent to a host and port and received with
their sender; and `Dns`, name lookup off the event loop's thread. A call that would block
waits for the event loop instead, so other tasks go on meanwhile.

## Types

### `UdpSocket`

```zsharp
type UdpSocket
```

A UDP socket (`Udp.bind`); `use` closes it.

#### `UdpSocket`

```zsharp
| UdpSocket of int
```

The socket's file descriptor.

## Derives and impls

### `impl Dispose<UdpSocket>`

```zsharp
impl Dispose<UdpSocket>
```

`use` closes the socket.

## Functions

### `Udp.bind`

```zsharp
Udp.bind : string -> int -> result<UdpSocket, string>
```

A socket bound to the host (a name or an address; "" for every interface) and port (0 for
one the system picks: `Udp.port` says which).

### `Udp.port`

```zsharp
Udp.port : UdpSocket -> int
```

The port the socket is bound to.

### `Udp.send`

```zsharp
Udp.send : UdpSocket -> string -> int -> Buffer<u8> -> int -> Task<result<unit, string>>
```

Sends the buffer's first `n` bytes as one datagram to the host and port, waiting while the
socket can't take it.

### `Udp.sendText`

```zsharp
Udp.sendText : UdpSocket -> string -> int -> string -> Task<result<unit, string>>
```

Sends the text's bytes as one datagram.

### `Udp.receive`

```zsharp
Udp.receive : UdpSocket -> Buffer<u8> -> Task<result<int * string * int, string>>
```

Waits for a datagram into the buffer: the bytes received (a longer datagram is cut to the
buffer), and the sender's address and port.

### `Dns.lookup`

```zsharp
Dns.lookup : string -> Task<list<string>>
```

The addresses of a host (IPv4 and IPv6, as text, each once), looked up off the event loop's
thread (`Task.blocking`) so other tasks go on meanwhile; an empty list for a name that has
none.

