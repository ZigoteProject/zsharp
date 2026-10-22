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

### `File.exists`

```zsharp
File.exists : string -> bool
```

Whether `path` names an existing regular file.

