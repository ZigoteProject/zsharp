# IO.Stream

Readers and writers: a file, a pipe or a standard stream read or written through a buffer,
as bytes or as text. They block, as reading a file does; a task that must not stall its loop
reads on `Task.blocking`'s thread. `use` closes one (a writer is flushed first).

## Types

### `Reader`

```zsharp
type Reader
```

A stream being read (`File.openRead`, `Console.openStandardInput`, a process's piped output).

### `Writer`

```zsharp
type Writer
```

A stream being written (`File.openWrite`, `Console.openStandardOutput`, a process's piped
input): bytes collect in `buffer` until it's full or flushed.

## Derives and impls

### `impl Dispose<Reader>`

```zsharp
impl Dispose<Reader>
```

`use` closes the stream.

### `impl Dispose<Writer>`

```zsharp
impl Dispose<Writer>
```

`use` flushes what's waiting, then closes the stream.

## Functions

### `Reader.ofFd`

```zsharp
Reader.ofFd : int -> Reader
```

A reader of an open file descriptor (it closes it when it's disposed).

### `Reader.readLine`

```zsharp
Reader.readLine : Reader -> result<option<string>, string>
```

The next line, without its line ending (`\n` or `\r\n`); `None` at the end. A last line
without a newline is a line.

### `Reader.readBytes`

```zsharp
Reader.readBytes : Reader -> Buffer<u8> -> result<int, string>
```

Reads into `buf`, up to its length: how many bytes came, 0 at the end.

### `Reader.readExactly`

```zsharp
Reader.readExactly : Reader -> Buffer<u8> -> int -> result<unit, string>
```

Reads exactly `n` bytes into the start of `buf` (an LSP message's `Content-Length`); an
`Error` when the stream ends first.

### `Reader.readToEnd`

```zsharp
Reader.readToEnd : Reader -> result<string, string>
```

What's left of the stream, as text.

### `Writer.ofFd`

```zsharp
Writer.ofFd : int -> Writer
```

A writer of an open file descriptor (it closes it when it's disposed).

### `Writer.flush`

```zsharp
Writer.flush : Writer -> result<unit, string>
```

Writes what's waiting to the stream.

### `Writer.write`

```zsharp
Writer.write : Writer -> span<u8> -> result<unit, string>
```

Writes the bytes (an array, a Buffer, a slice or `String.bytes s`).

### `Writer.writeText`

```zsharp
Writer.writeText : Writer -> string -> result<unit, string>
```

Writes the text's bytes.

