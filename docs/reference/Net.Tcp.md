# Net.Tcp

TCP connections for tasks: listening, accepting, connecting, reading and writing. A call
that would block waits for the event loop instead, so other tasks go on meanwhile.

## Types

### `TcpListener`

```zsharp
type TcpListener
```

A socket listening for connections (`Tcp.listen`); `use` closes it.

#### `TcpListener`

```zsharp
| TcpListener of int
```

The socket's file descriptor.

### `TcpStream`

```zsharp
type TcpStream
```

A connection (`Tcp.accept`, `Tcp.connect`); `use` closes it.

#### `TcpStream`

```zsharp
| TcpStream of int
```

The socket's file descriptor.

## Derives and impls

### `impl Dispose<TcpListener>`

```zsharp
impl Dispose<TcpListener>
```

`use` closes the listening socket.

### `impl Dispose<TcpStream>`

```zsharp
impl Dispose<TcpStream>
```

`use` closes the connection.

## Functions

### `Tcp.listen`

```zsharp
Tcp.listen : string -> int -> result<TcpListener, string>
```

A socket listening on the host (a name or an address; "" for every interface) and port.

### `Tcp.accept`

```zsharp
Tcp.accept : TcpListener -> Task<result<TcpStream, string>>
```

Waits for the next connection.

### `Tcp.connect`

```zsharp
Tcp.connect : string -> int -> Task<result<TcpStream, string>>
```

A connection to the host and port.

### `Tcp.read`

```zsharp
Tcp.read : TcpStream -> Buffer<u8> -> Task<result<int, string>>
```

Reads what has come into the buffer, waiting until something has: the number of bytes
read, 0 once the other end has closed the connection.

### `Tcp.write`

```zsharp
Tcp.write : TcpStream -> Buffer<u8> -> int -> Task<result<unit, string>>
```

Writes the buffer's first `n` bytes, waiting while the connection can't take more.

### `Tcp.writeText`

```zsharp
Tcp.writeText : TcpStream -> string -> Task<result<unit, string>>
```

Writes the text's bytes, waiting while the connection can't take more.

