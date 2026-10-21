# Console

The console: standard input, output and error.

## Functions

### `Console.write`

```zsharp
Console.write : string -> unit
```

Writes the string to standard output, without a newline.

### `Console.writeLine`

```zsharp
Console.writeLine : string -> unit
```

Writes the string and a newline to standard output.

### `Console.readLine`

```zsharp
Console.readLine : unit -> option<string>
```

The next line of standard input without its newline, or `None` at the end.

### `Console.readLines`

```zsharp
Console.readLines : unit -> list<string>
```

All of standard input, line by line (without the newlines).

### `Console.Error.writeLine`

```zsharp
Console.Error.writeLine : string -> unit
```

Writes the string and a newline to standard error.

