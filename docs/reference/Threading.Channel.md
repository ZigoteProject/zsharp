# Threading.Channel

Channels: a `Channel<T>` carries values from threads that send them to threads that receive
them, in order, holding up to the capacity it was made with (a sender waits while it's full).
Its values must be Share. Its functions are built into the compiler.

## Functions

### `Channel.close`

```zsharp
Channel.close : Channel<'a> -> unit
```

Closes the channel: receivers get what's left, then `None`; a send panics.

### `Channel.make`

```zsharp
Channel.make : int -> Channel<'a>
```

A channel holding up to `capacity` values (at least 1).

### `Channel.receive`

```zsharp
Channel.receive : Channel<'a> -> option<'a>
```

The next value, waiting for one: `None` once the channel is closed and empty.

### `Channel.send`

```zsharp
Channel.send : Channel<'a> -> 'a -> unit
```

Sends `x`, waiting while the channel is full. Panics once it's closed.

