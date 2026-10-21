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

### `Directory.exists`

```zsharp
Directory.exists : string -> bool
```

Whether `path` names an existing directory.

