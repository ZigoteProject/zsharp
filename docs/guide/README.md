# The Z# Guide

Z# is a functional-first language with F# syntax that compiles to native code through LLVM.
- **No VM or garbage collector:** memory is managed by reference counting that the compiler inserts and optimizes.
- **C interop:** calling C and being called from C need no glue code.

This guide teaches the language through small, complete programs. Every example here is
compiled and run by the test suite (`tests/docs.sh`), and the text block after an example is
its exact output.

1. [Getting started](01-getting-started.md): installing, the first program, `zs` commands, editor setup
2. [Basics](02-basics.md): values, functions, numbers, strings, control flow, mutation
3. [Data](03-data.md): tuples, records, unions, options and results, pattern matching
4. [Functions](04-functions.md): closures, pipelines, generics, members and named arguments
5. [Collections](05-collections.md): lists, arrays and Buffers, Map, Set, HashMap
6. [Traits](06-traits.md): operators, equality and printing, impls, `dyn` values, derives
7. [Errors](07-errors.md): results and `?`, panics, overflow
8. [Programs](08-programs.md): modules, projects and dependencies, files and processes, tests, units of measure
9. [C interop](09-c-interop.md): `extern`, `import c`, structs by value, callbacks, pointers and `unsafe`, exporting to C (handles, shared libraries), cross-compiling
10. [Tools](10-tools.md): the `zs` command line, formatting, docs, debugging, Zed and other editors
11. [Microcontrollers](11-microcontrollers.md): bare-metal Cortex-M, hardware registers, fast and small code
12. [Memory](12-memory.md): reference counting, cycles and weak references, arenas
13. [Computation expressions and tasks](13-tasks.md): `option { }`, `result { }`, `task { }`, running tasks at once, cancellation, sockets
14. [Parallelism](14-parallel.md): the thread pool, what can cross threads (`Share`), `Atomic`, `Mutex` and `Channel`, tasks on every core
15. [SIMD](15-simd.md): vectors, masks and shuffles, `[<FastMath>]`, CPU targets and multiversioning, intrinsics

**Reference:**
- [The library reference](../reference/README.md), generated from its doc comments by `zs doc`.
- [DESIGN.md](../../DESIGN.md), the language design and the reasons behind it.
- [ROADMAP.md](../../ROADMAP.md), what's done and what's next.
