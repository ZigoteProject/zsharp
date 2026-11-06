# Net.Unix

Unix sockets for tasks: `Tcp`'s calls over a path in the file system instead of a host and
a port, for processes on one machine (the build server's socket). A listener and a connection
are `Tcp`'s types, so `Tcp.read`, `Tcp.write` and `use` work on them as they are.

## Functions

### `Unix.listen`

```zsharp
Unix.listen : string -> result<TcpListener, string>
```

A socket listening at `path`. A socket an earlier run left there (one no server listens
on) is removed first; anything else there is an error, a file or a live server's socket.

### `Unix.accept`

```zsharp
Unix.accept : TcpListener -> Task<result<TcpStream, string>>
```

Waits for the next connection: `Tcp.accept`, which takes a Unix listener too.

### `Unix.connect`

```zsharp
Unix.connect : string -> Task<result<TcpStream, string>>
```

A connection to the socket at `path`. Cancelled before it has connected, it closes the
socket it was connecting.

