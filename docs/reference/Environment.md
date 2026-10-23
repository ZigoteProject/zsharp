# Environment

The program's environment: its command-line arguments and environment variables.
`Environment.exit code` ends the program.

## Functions

### `Environment.args`

```zsharp
Environment.args : unit -> list<string>
```

The command-line arguments, without the program name.

### `Environment.programName`

```zsharp
Environment.programName : unit -> string
```

The program name as it was started (`argv[0]`).

### `Environment.getVariable`

```zsharp
Environment.getVariable : string -> option<string>
```

The environment variable `name`, or `None` when it isn't set.

### `Environment.currentDirectory`

```zsharp
Environment.currentDirectory : unit -> string
```

The working directory, as an absolute path.

### `Environment.exit`

```zsharp
Environment.exit : int -> 'a
```

Ends the program now with the exit code (output is flushed; nothing else is cleaned up).

