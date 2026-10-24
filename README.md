# Z#

Z# is a functional-first programming language with F# syntax that compiles to native code
through LLVM.
- **Memory:** no garbage collector or VM. The compiler inserts and optimizes reference counting.
- **C interop:** direct, including `import c "header.h"`.
- **Targets:** Linux, macOS and Windows on x86-64 and aarch64, and bare-metal Cortex-M microcontrollers.

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
| Functions | closures, pipelines whose lambdas take their types from the call, custom operators, members with named and optional arguments |
| Types | traits for operators, equality, ordering and printing; derived for records and unions, or written as derives in Z#; `dyn` values |
| Effects | effect handlers with inferred, row-polymorphic effect types (`int / Throw<string>`): generators (`seq { }`, `Seq`), typed exceptions (`Throw`), handlers of a program's own; pure code compiles as if they didn't exist |
| Concurrency | `task { }` on an event loop per thread, compiled to state machines (a wait allocates nothing): timers, TCP sockets, `both`/`all`/`race`, scopes, cancellation that disposes `use` values, `Task.spawn` onto every core; `option { }` and `result { }` |
| Parallelism | a work-stealing thread pool (`Parallel.both`/`for`/`reduce`, `Array.Parallel`), `Atomic`, `Mutex`, `Channel`; what crosses threads is checked at compile time, and only shared objects have atomic reference counts |
| SIMD | portable vectors (`f32x8`, `u8x16`, … with masks and shuffles), `[<FastMath>]`, `--cpu`, `[<Target>]`, `[<Multiversion>]`, x86-64 and aarch64 intrinsics; within 10% of C with intrinsics |
| Values | copy-on-write arrays, persistent `Map`/`Set`, `HashMap`, checked integer overflow, weak references, arenas |
| Performance | at C's speed or better on the [host benchmarks](docs/reports/host.md), with at most C's peak memory, except `fib` at 1.76×, all overflow checks (C with the same checks takes the same time); [as fast as C](docs/reports/microcontrollers.md) on Cortex-M compute code; ThinLTO and PGO |
| Projects | `zs.toml` with path and git dependencies, `zs test`, `zs fmt`, `zs doc` |
| C | `extern`, `import c`, structs by value (System V and AAPCS64), callbacks, C function pointers, raw pointers in `unsafe`, `[<Export>]` static and shared libraries holding Z# objects as handles |
| Debugging and targets | DWARF debug info for gdb; cross-compiling with `--target` (`aarch64-linux-musl`, or `cortex-m4` and `cortex-m0plus` bare metal) |
| Editors | Zed extension, `zs lsp` for any editor, `zs mcp` for AI agents |

## Getting started

```sh
./dev ./test.sh                 # build the compiler and run the tests in the dev container
./dev bin/zs run hello.zs
```

Read **[the guide](docs/guide/README.md)** to learn the language. [DESIGN.md](DESIGN.md) covers
the design and the reasons behind it, [ROADMAP.md](ROADMAP.md) what's done and what's next, and
[docs/proposals](docs/proposals/README.md) the designs under discussion.

## Status

Z# is pre-1.0: the language and the library still change between releases. The compiler is
written in Z# and builds itself; `./dev` fetches the previous release (stage 0, pinned in `dev`)
from this repository's [GitHub releases](https://github.com/ZigoteProject/zsharp/releases) on first use.
It needs [podman](https://podman.io).

## License

Z# is under the [MIT license](LICENSE). It includes:

| Component | Where | License |
|---|---|---|
| [xxHash](https://github.com/Cyan4973/xxHash) | `packages/xxhash/c` | [BSD 2-Clause](packages/xxhash/c/LICENSE) |
| [wepoll](https://github.com/piscisaureus/wepoll) | `runtime/wepoll` | [BSD 2-Clause](runtime/wepoll/LICENSE) |
| [tree-sitter](https://github.com/tree-sitter/tree-sitter)'s parser headers | `editors/tree-sitter-zsharp/src/tree_sitter` | [MIT](editors/tree-sitter-zsharp/src/tree_sitter/LICENSE) |

`import c` opens the system's libclang (LLVM, Apache 2.0 with LLVM exceptions) at run time; none
of LLVM is shipped.
