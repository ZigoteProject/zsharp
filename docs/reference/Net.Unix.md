# Net.Unix

Unix sockets for tasks: `Tcp`'s calls over a path in the file system instead of a host and
a port, for processes on one machine (the build server's socket). A listener and a connection
are `Tcp`'s types, so `Tcp.read`, `Tcp.write` and `use` work on them as they are.

## Functions

### `Unix.listen`

```zsharp
Unix.listen : string -> result<TcpListener, string>
```

A socket listening at `path`; a socket file left there by an earlier run is removed first.

### `Unix.accept`

```zsharp
Unix.accept : TcpListener -> Task<result<TcpStream, string>>
```

Waits for the next connection: `Tcp.accept`, which takes a Unix listener too.

### `Unix.connect`

```zsharp
Unix.connect : string -> Task<result<TcpStream, string>>
```

A connection to the socket at `path`.

