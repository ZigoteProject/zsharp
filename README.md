# Z#

Z# is a functional-first programming language with F# syntax that compiles to native code
through LLVM.
- **Memory:** no garbage collector or VM. The compiler inserts and optimizes reference counting.
- **C interop:** direct, including `import c "header.h"`.
- **Targets:** x86-64 and aarch64.

```fsharp
type Shape =
  | Circle of radius: f64
  | Rect of w: f64 * h: f64

let area s =
  match s with
  | Circle r -> 3.14159 * r * r
  | Rect (w, h) -> w * h

let main () =
  let shapes = [ Circle 1.0; Rect (2.0, 3.0) ]
  println $"total area {shapes |> List.sumBy area}"
  0
```

## What's here

| Feature | |
|---|---|
| Data | records with defaults, unions, pattern matching with exhaustiveness checks, active patterns, units of measure |
| Types | traits for operators, equality, ordering and printing; derived for records and unions, or written as derives in Z# |
| Values | copy-on-write arrays, persistent `Map`/`Set`, `HashMap`, checked integer overflow |
| Projects | `zs.toml` with path and git dependencies, `zs test`, `zs fmt`, `zs doc` |
| C | `extern`, `import c`, structs by value (System V and AAPCS64), callbacks, `[<Export>]` libraries |
| Debugging and targets | DWARF debug info for gdb; cross-compiling with `--target` (e.g. `aarch64-linux-musl`) |
| Editors | Zed extension, `zs lsp` for any editor, `zs mcp` for AI agents |

## Getting started

```sh
./dev ./test.sh                 # build the compiler and run the tests in the dev container
./dev bin/zs run hello.zs
```

Read **[the guide](docs/guide/README.md)** to learn the language. [DESIGN.md](DESIGN.md) covers
the design and the reasons behind it, and [ROADMAP.md](ROADMAP.md) what's done and what's next.
