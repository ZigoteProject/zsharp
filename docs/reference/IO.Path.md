# IO.Path

File paths as text, with `/` between the parts: joining them and taking them apart. Nothing
here touches the file system.

## Functions

### `Path.combine`

```zsharp
Path.combine : string -> string -> string
```

`a` and `b` joined with a `/`; `b` itself when it is absolute (starts with `/`).

### `Path.getFileName`

```zsharp
Path.getFileName : string -> string
```

The part after the last `/`: `"main.zs"` for `src/main.zs`.

### `Path.getDirectoryName`

```zsharp
Path.getDirectoryName : string -> string
```

The part before the last `/`: `"src"` for `src/main.zs`, `"/"` for `/etc`, and `""` when
there is no `/`.

### `Path.getExtension`

```zsharp
Path.getExtension : string -> string
```

The file name's extension with its dot (`".zs"`), or `""` when it has none. A name that
only starts with a dot, like `.gitignore`, has none.

### `Path.getFileNameWithoutExtension`

```zsharp
Path.getFileNameWithoutExtension : string -> string
```

The file name without its extension: `"main"` for `src/main.zs`.

### `Path.changeExtension`

```zsharp
Path.changeExtension : string -> string -> string
```

The path with its extension replaced by `ext` (`".md"` or `"md"`); `""` removes it.

