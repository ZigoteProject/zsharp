# Changelog

## Unreleased

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
