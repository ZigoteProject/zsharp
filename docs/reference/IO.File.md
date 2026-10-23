# IO.File

Reading and writing whole files. A failure is an `Error` with a readable message, such as
`cannot open data.txt: No such file or directory`. `File.exists path` tests for one.

## Functions

### `File.readAllText`

```zsharp
File.readAllText : string -> result<string, string>
```

The whole file as a string.

### `File.readAllLines`

```zsharp
File.readAllLines : string -> result<list<string>, string>
```

The file's lines, without line endings; a final newline doesn't add an empty line.

### `File.writeAllText`

```zsharp
File.writeAllText : string -> string -> result<unit, string>
```

Replaces the file's contents with `text` (creating it if needed).

### `File.writeAllLines`

```zsharp
File.writeAllLines : string -> list<string> -> result<unit, string>
```

Replaces the file's contents with the lines, each ending in a newline.

### `File.appendAllText`

```zsharp
File.appendAllText : string -> string -> result<unit, string>
```

Adds `text` to the end of the file (creating it if needed).

### `File.readAllTextAsync`

```zsharp
File.readAllTextAsync : string -> Task<result<string, string>>
```

The whole file as a string, read on `Task.blocking`'s helper thread so tasks go on meanwhile.

### `File.writeAllTextAsync`

```zsharp
File.writeAllTextAsync : string -> string -> Task<result<unit, string>>
```

Replaces the file's contents with `text`, on `Task.blocking`'s helper thread.

### `File.delete`

```zsharp
File.delete : string -> result<unit, string>
```

Deletes the file.

### `File.openRead`

```zsharp
File.openRead : string -> result<Reader, string>
```

The file opened to read, through a buffer; `use` closes it.

### `File.openWrite`

```zsharp
File.openWrite : string -> result<Writer, string>
```

The file opened to write, emptied first (or created); `use` flushes and closes it.

### `File.openAppend`

```zsharp
File.openAppend : string -> result<Writer, string>
```

The file opened to write at its end (or created); `use` flushes and closes it.

### `File.readAllBytes`

```zsharp
File.readAllBytes : string -> result<array<u8>, string>
```

The whole file's bytes, as they are (not read as text).

### `File.writeAllBytes`

```zsharp
File.writeAllBytes : string -> span<u8> -> result<unit, string>
```

Replaces the file's contents with the bytes, as they are (creating it if needed).

### `File.copy`

```zsharp
File.copy : string -> string -> result<unit, string>
```

Copies the file to `target`, replacing what's there.

### `File.move`

```zsharp
File.move : string -> string -> result<unit, string>
```

Moves the file to `target`, replacing what's there: a rename, or a copy and a delete from
another file system.

### `File.modifiedAt`

```zsharp
File.modifiedAt : string -> result<DateTime, string>
```

When the file was last changed.

### `File.size`

```zsharp
File.size : string -> result<i64, string>
```

The file's size in bytes.

### `File.touch`

```zsharp
File.touch : string -> result<unit, string>
```

Marks the file changed now (its modification time), as `touch` does.

### `File.createTemp`

```zsharp
File.createTemp : string -> result<string, string>
```

A new empty file in the temporary directory (`$TMPDIR`, else `/tmp`), named `prefix` and six
characters, readable by its owner only: its path.

### `File.exists`

```zsharp
File.exists : string -> bool
```

Whether `path` names an existing regular file.

