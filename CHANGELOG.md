# Changelog

## Unreleased

### Language
- Patterns at the top level: `let (width, height) = (800, 600)` declares both names. A tuple of
  constants stays constants; anything else is computed once at startup. A local `let`'s pattern
  takes an annotation (`let (a, b): int * string = …`), and a `let` whose pattern can fail says
  so: `a let's pattern must match every value, and this one misses None`.
- Layout facts: `sizeof<T>`, `alignof<T>` and `offsetof<T> "field"` are `int` constants for the
  target, a `[<CLayout>]` type's as C lays it out. A top-level `assert` on constants is checked
  when compiling (`assert (sizeof<Packet> = 16)`), naming what it read when it fails; any other
  top-level `assert` runs at startup. The header `zs build --lib` writes checks each struct's size
  with `_Static_assert`.
- A public constant that uses a private one of its module works from other modules (it was
  `'x' is private to module M` at the use).
- A `type private` record's fields are private too: outside its module, code can't read, set,
  build or match them, even on a value it reached through a public record's field.
- A task cancelled at a wait no longer leaks a value it took apart with a tuple pattern
  (`let! (x, reply, nack) = …`) before that wait.

### Platforms
- C interop on a microcontroller, both ways: structs by value follow AAPCS (they were passed
  with x86-64's rules), hard and soft float; `[<Link>]` C sources are compiled for the chip; C
  callbacks work there. `zs build --lib --target cortex-m4` makes an archive and its header for a
  C firmware, which takes the library's output, stop and ticks by defining `zs_write`,
  `zs_stop` and `zs_ticks`.
- WebAssembly: `[<Link>]` C sources are linked in, and `--lib -o lib.a` makes an archive for a C
  program built for WebAssembly.
- An exported function that returns a struct through memory declares the struct's own alignment
  for the pointer it's given (it said 8, which lets a Cortex-M fault on a 4-aligned struct).

### Editor
- A VS Code extension (`editors/vscode`) and a Rider plugin (`editors/rider`, any JetBrains IDE
  2025.2 or later): highlighting, the language server and, in VS Code, the MCP server for the
  agent, as the Zed extension gives. Both share one TextMate grammar.

## 0.6.1 (2026-10-25)

The first release for more than Linux: the compiler for Linux x86-64, macOS arm64 and
Windows x64, each built by the macOS one (`src/release.sh`).

### Platforms
- `zs build --target` takes `aarch64-macos`, `x86_64-macos`, `x86_64-windows-gnu`,
  `aarch64-windows-gnu`, `aarch64-linux-gnu` and `wasm32` (freestanding, with a Node host):
  clang compiles the IR, zig cc the runtime and the link, no SDK.
- The compiler runs on macOS and Windows. On Windows, a build without `--target` goes through
  mingw-w64; file names, arguments and the environment are UTF-8; paths work across drives.
- The runtime's loop on epoll, kqueue and IOCP (wepoll); sockets, processes and pipes on Windows.
- Cross builds are the same bytes each time; ThinLTO caches on macOS.

### Compiler
- Every mistake of a declaration is reported, not only its first.
- The back half of the compiler runs on all cores; it builds itself faster than the F# compiler did.
- Optimized builds drop what nothing reaches: a hello world is 17 KB, not 89.
- `import c` works from a fresh clone, and for a target finds its system headers.
- A project's modules are found from its main's folder, in any subfolder.

### Editor
- LSP: a function's signature at the end of its line; hover, references and definition of
  type names.

### Library
- `Task.run` waits for the spawned tasks it cancelled.

### Fixes
- A dependency's name can't reach outside `.zs-cache/deps`; a rev starting with `-` isn't
  passed to git as an option; MCP tools refuse symbolic links.
- A file with a top-level expression reports a parse error instead of panicking.
- The Windows runtime builds with newer mingw-w64 headers, which declare `mkdtemp`.

### Other
- MIT license; `examples/logstat`, a Z# tour for F# developers.

## 0.6 (2026-10-24)

The compiler in Z#, beside the F# one (the last version with both). Stage 0 for building `src/`.
