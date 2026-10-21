# 10. Tools

## The zs command

| Command | Does |
|---|---|
| `zs new <name>` | create a project |
| `zs build [file.zs] [-o out]` | build an executable (the project's, without a file) |
| `zs run [file.zs [--]] [args…]` | build and run |
| `zs check <file.zs>` | type-check only, reporting every error |
| `zs test [file.zs] [filters…]` | run `[<Test>]` functions, each in its own process |
| `zs fmt [--check] <files…>` | format files in place (`--check`: list unformatted ones) |
| `zs doc <file.zs>` | print a Markdown reference of a file's documented items |
| `zs fetch` / `zs update` | check out / update git dependencies |
| `zs lsp` | the language server (stdio) |
| `zs mcp` | the MCP server for AI agents (stdio) |

**Build options:**

| Option | Does |
|---|---|
| `-g` | debug info, unoptimized ([Debugging](#debugging)) |
| `--target <triple>` | cross-compile ([C interop](09-c-interop.md#cross-compiling)) |
| `--lib` | a static library plus a C header |
| `--sanitize` | AddressSanitizer and UndefinedBehaviorSanitizer |
| `--emit-llvm` | keep the LLVM IR (`out.ll`) |
| `--time` | how long each compiler phase took |

**Environment variables:**
- `ZS_BACKTRACE=0` leaves backtraces out of panic output.
- `ZS_ABORT=1` makes a panic a real `abort()`, with a core dump for a debugger.
- `ZS_LEAKCHECK=1` reports heap objects still allocated at exit.

## Formatting

**What `zs fmt` does:** it applies the one canonical layout, with no options:
- two-space indentation;
- consistent spacing around operators and punctuation;
- trimmed trailing whitespace;
- at most one blank line in a row.

**Safety:** comments stay where they are, and the formatter checks that the result has exactly the same tokens as the input, so formatting can't change a program's meaning. Zed runs it on save.

## Documentation comments

`///` comments above a declaration document it. They work on functions, types, union cases, traits and their methods, and members.
- **Where they show:** in hover and completion in the editor, in the MCP `docs` tool, and in `zs doc`'s Markdown output.
- **The library:** it's fully documented this way. [Its reference](../reference/README.md) is generated with `zs doc`, one page per module.

```zsharp
/// A point on the screen, in pixels.
type Point = { x: int; y: int }

/// The distance between two points, moving only along the axes.
let manhattan (a: Point) (b: Point) = Math.abs (a.x - b.x) + Math.abs (a.y - b.y)

let main () =
  println $"{manhattan { x = 1; y = 1 } { x = 4; y = 5 }}"
  0
```

```text
7
```

## Debugging

`zs build -g` builds without optimization and with DWARF debug info, so gdb works with the Z# source:
- **Breakpoints and stepping:** break on a function (`break square`) or a line (`break prog.zs:12`), then step with `next` and `step`.
- **Backtraces:** `bt` shows Z# files and lines.
- **Values:** arguments and local variables of number and bool types are shown.

```
Breakpoint 1, square (n=1) at prog.zs:3
3	  let result = n * n
(gdb) bt
#0  square (n=1) at prog.zs:3
#1  main () at prog.zs:9
```

**Memory checking:** `--sanitize` builds with AddressSanitizer and UndefinedBehaviorSanitizer, and valgrind works on any build.

## Editors

### Zed

`editors/zed` is a Zed extension. Install it with **Extensions → Install Dev Extension** and choose that folder. It needs Rust, with the `wasm32-wasip2` target installed through rustup.

**What it gives:**
- tree-sitter highlighting and outline;
- the `zs lsp` language server: errors as you type, hover with types and docs, go to definition, references, completion, inlay type hints, document symbols and formatting;
- the `zs mcp` context server, so Zed's agent can check, build and run code and look up documentation.

The extension finds `zs` on your `PATH`. Or set the path in Zed's settings:

```json
"lsp": { "zs": { "binary": { "path": "/path/to/zs", "arguments": ["lsp"] } } },
"context_servers": { "zs": { "command": "/path/to/zs", "args": ["mcp"] } }
```

### Other editors

Run `zs lsp` over stdio as the language server for `.zs` files. The tree-sitter grammar is in `editors/tree-sitter-zsharp`, with highlight, indent and outline queries. `zs mcp` works with any MCP client.
