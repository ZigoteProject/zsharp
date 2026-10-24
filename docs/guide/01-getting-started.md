# 1. Getting started

## Building the compiler

The compiler is written in Z# itself (`src/`). It drives clang to produce native executables, and
builds itself with the previous release of the compiler (stage 0).

**The dev container (recommended):** the repository's development environment is a container with everything the compiler and its tests need: clang and LLVM, zig, qemu, gdb and valgrind, and the stage-0 compiler. `./dev` runs a command inside it, building the image the first time:

```sh
./dev ./test.sh                  # build the compiler and run every test
./dev bin/zs run hello.zs        # use the freshly built compiler
```

**Without the container:** you need clang, and a `zs` from a release (or from the container) to build `src/` with:

```sh
zs build src/Main.zs --release -o zs-new && src/install.sh zs-new bin   # bin/zs, its library and runtime beside it
```

## Hello, world

```zsharp
let main () =
  println "Hello, world!"
  0
```

```text
Hello, world!
```

**How a program is laid out:**
- Every program has a `main` function. Its `int` result is the process's exit code.
- Indentation marks blocks, as in F# and Python: the body of `main` is the indented lines under it.
- The last expression of a block is its value. Here it's `0`.

Save it as `hello.zs`, then:

```sh
zs run hello.zs          # build and run
zs build hello.zs        # build ./hello
./hello
zs build hello.zs --release   # optimized, for measuring and shipping
```

A plain `zs build` is a debug build: quick to make, its code unoptimized. `--release` optimizes the program and, across its files, inlines at the link (ThinLTO), which takes longer ([Programs](08-programs.md#builds)).

## A project

For anything bigger than one file, create a project:

```sh
zs new greeter
cd greeter
zs run                   # builds and runs src/main.zs
zs run Ada               # program arguments follow
zs test                  # runs the tests ([<Tests>] values)
```

`zs new` writes these files:
- `zs.toml`: the manifest.
- `src/main.zs`: a program with a function, a `main` and a test.
- `.gitignore`: ignores the build output.

Projects, modules and dependencies are covered in [Programs](08-programs.md).

## Editors

**Zed:** the repository has a Zed extension (`editors/zed`). It gives syntax highlighting, the language server (errors as you type, hover types and docs, go to definition, completion, formatting) and an MCP server for Zed's agent. [Tools](10-tools.md#editors) describes the setup.

**Other editors:** run `zs lsp` as the language server for `.zs` files. The tree-sitter grammar in `editors/tree-sitter-zsharp` works in editors that use tree-sitter.

## Comments

```zsharp
// a line comment

/// A doc comment: shown when hovering over `area`, and in `zs doc` output.
let area (w: f64) (h: f64) = w * h

let main () =
  println $"{area 2.0 3.5}" // comments can follow code
  0
```

```text
7
```
