# IO.Directory

Directories: creating and listing them. `Directory.exists path` tests for one.

## Functions

### `Directory.create`

```zsharp
Directory.create : string -> result<unit, string>
```

Creates the directory; an existing one is fine.

### `Directory.list`

```zsharp
Directory.list : string -> result<list<string>, string>
```

The names in the directory (not `.` or `..`), sorted.

### `Directory.temp`

```zsharp
Directory.temp : unit -> string
```

The directory for temporary files: `$TMPDIR`, else `/tmp` (on Windows `%TMP%`, else
`%TEMP%`).

### `Directory.createTemp`

```zsharp
Directory.createTemp : string -> result<string, string>
```

A new empty directory in the temporary directory, named `prefix` and six characters: its path.

### `Directory.delete`

```zsharp
Directory.delete : string -> result<unit, string>
```

Deletes the directory, which must be empty.

### `Directory.listRecursive`

```zsharp
Directory.listRecursive : string -> result<list<string>, string>
```

The paths of every file and directory under `path`, relative to it, sorted; a symbolic link
is listed and not followed.

### `Directory.deleteRecursive`

```zsharp
Directory.deleteRecursive : string -> result<unit, string>
```

Deletes the directory and everything under it (a symbolic link as itself, not what it
points to).

### `Directory.exists`

```zsharp
Directory.exists : string -> bool
```

Whether `path` names an existing directory.

