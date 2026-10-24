# IO.Path

File paths as text, with `/` between the parts (on Windows `\`, and `/` is one too):
joining them and taking them apart. Nothing here touches the file system (`getFullPath`
reads the working directory). Paths compare as strings, case and all.

## Functions

### `Path.separator`

```zsharp
let separator
```

The character between a path's parts: `\` on Windows, else `/`.

### `Path.isAbsolute`

```zsharp
Path.isAbsolute : string -> bool
```

Whether the path starts at a root: `/`; on Windows also `\`, a drive's (`C:\`) or a share
(`\\server\share`).

### `Path.combine`

```zsharp
Path.combine : string -> string -> string
```

`a` and `b` joined with a separator; `b` itself when it is absolute. A bare drive joins
without one (`C:x`, relative to that drive), as .NET's `Path.Combine`.

### `Path.getFileName`

```zsharp
Path.getFileName : string -> string
```

The part after the last separator: `"main.zs"` for `src/main.zs`.

### `Path.getDirectoryName`

```zsharp
Path.getDirectoryName : string -> string
```

The part before the last separator: `"src"` for `src/main.zs`, `"/"` for `/etc` (`C:\` for
`C:\a`), and `""` when there is none.

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

### `Path.getFullPath`

```zsharp
Path.getFullPath : string -> string
```

The path made absolute against the working directory, with `.`, `..` and repeated
separators worked out on the text (symbolic links aren't followed), as .NET's
`Path.GetFullPath`.

### `Path.getRelativePath`

```zsharp
Path.getRelativePath : string -> string -> string
```

The path of `path` from the directory `from`: `getRelativePath "/a/b" "/a/c/d"` is
`"../c/d"`, and `"."` for the same place.

