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
- C unions: a `[<CLayout>]` union has no tag, each case a view of the same bytes. It's built by
  case (the bytes after the case's field zero) and read by case name inside `unsafe`
  (`unsafe d.U32`); it can't be matched, compared or printed. It crosses to C by value as C
  passes a union on every target, sits in `[<CLayout>]` records, and is declared in `--lib`
  headers; debuggers show it as C's. Hovering a `[<CLayout>]` type shows its size and alignment.
- The `cycle` warning (0021): a type whose objects can form a reference cycle through a `ref`,
  `Buffer`, `Mutex` or `Channel` (two ways back, or two types reaching each other), which
  counting never frees, is warned where it's declared, with the path and notes at the other
  types' fields, and the fixes: a `weak` back-pointer, `[<Cyclic>]` on a type whose cycles the
  program breaks, or `[<NoWarn "cycle">]`.
- A public constant that uses a private one of its module works from other modules (it was
  `'x' is private to module M` at the use).
- A `type private` record's fields are private too: outside its module, code can't read, set,
  build or match them, even on a value it reached through a public record's field.
- A task cancelled at a wait no longer leaks a value it took apart with a tuple pattern
  (`let! (x, reply, nack) = …`) before that wait.

### Platforms
- Interrupt handlers (0012): `[<Interrupt 38>]`, `[<Interrupt "UARTRX0">]` (the board's names,
  `runtime/boards/<board>.irq`) or `[<Interrupt "SysTick">]`/`"HardFault"`/… on a
  `unit -> unit` function make it the line's handler over the runtime's weak defaults. A handler
  may reach only what's `Share` (`interrupt handler 'tick' uses the top-level value 'count' :
  ref<int>, …`); `Atomic` is in Core now (masking interrupts on a Cortex-M0), and `Spsc<'a>` is a
  queue of one producer and one consumer that neither waits nor locks. `Irq.enable`, `disable`
  and `pend`.
- `Cpu` (0012): `wfi`, `wfe`, `sev`, `dmb`, `dsb`, `isb`, `nop`, `enableInterrupts`,
  `disableInterrupts`, one instruction each, and `Cpu.critical (fun () -> …)`, its body run with
  interrupts masked (it nests). On a computer the barriers are fences and the rest nothing; masking
  is an error there.
- `[<NoAlloc>]` and `--no-heap` (0012): a function that, or anything it calls, may allocate or
  free is an error naming the chain (`reply is [<NoAlloc>], but reply -> describe builds a
  string`); interrupt handlers and `Cpu.critical`'s bodies are checked the same way.
  `--no-heap` checks the whole program, startup values included, and builds a chip's image with
  no heap.
- A function that makes a span over a parameter (`Array.fold f 0 xs` over an array) borrows it.
- `Runtime.ticks` on a chip counts a SysTick wrap its handler hasn't run for yet, and never goes
  back (it could, by a wrap, right at one).
- An `[<Export>]` function returning `unit` compiles (the compiler panicked in its C wrapper).
- C interop on a microcontroller, both ways: structs by value follow AAPCS (they were passed
  with x86-64's rules), hard and soft float; `[<Link>]` C sources are compiled for the chip; C
  callbacks work there. `zs build --lib --target cortex-m4` makes an archive and its header for a
  C firmware, which takes the library's output, stop and ticks by defining `zs_write`,
  `zs_stop` and `zs_ticks`.
- WebAssembly: `[<Link>]` C sources are linked in, and `--lib -o lib.a` makes an archive for a C
  program built for WebAssembly.
- `import c` brings C unions in, a member a case named through its union (`epoll_data.fd 3`,
  `unsafe ev.data.fd`), and a struct or union without a name in a field as a type named after
  both (`Msg_body`). A struct with bit fields is left out, saying so (it was imported with every
  bit field a whole field, the wrong layout).
- `import c` in a build for a chip or WebAssembly reads the header as the target's compiler does
  (its triple and flags, freestanding), so a vendor's header sees the chip it's written for.
  `size_t` and `uintptr_t` are `usize`, and `ptrdiff_t`, `intptr_t` and `ssize_t` are `int`, on
  every target (they followed the target's C type: `u32` on a chip).
- A chip's runtime has C's `malloc`, `free`, `calloc`, `realloc` and `abort` (weak) over the Z#
  heap, for C, Rust or Zig code linked in; reuses freed blocks over 256 bytes (they were never
  reused); and has what Core needed that it lacked: `String.trim`, `toUpper`, `toLower`,
  `replace` and float parsing, `Ptr.alloc` and `Ptr.free`, handles for C, `Runtime.mallocs`.
- `zs.toml`: `target` under `[package]` (what `zs build` and `zs run` build for without
  `--target`), `[c.<target>]` sections added to `[c]` for one target (`host`, `cortex-m4`, a
  triple), and `[target.<name>]` with a chip's `heap`.
- `zs run` for a chip runs the image under QEMU on its board, and a WebAssembly module under Node.
- `examples/rust` and `examples/zig`: Rust and Zig code and packages with Z# through the C ABI,
  both ways, on an OS and on a Cortex-M4 under QEMU.
- macOS and Windows: a module's file is found by its exact name. Their file systems ignore case,
  so a file could be taken for a module of another name: `fixed.zs` for the library's `Fixed`,
  or `simd/x86.zs` for `Simd.X86`.
- An exported function that returns a struct through memory declares the struct's own alignment
  for the pointer it's given (it said 8, which lets a Cortex-M fault on a 4-aligned struct).

### Library
- `Math`: `floor`, `ceil`, `round` (half to even, as F#'s), `trunc`, `exp`, `log`, `log2`,
  `log10`, `sin`, `cos`, `tan`, `pow` and `atan2` for `f64` and `f32`, as LLVM's intrinsics (an
  instruction where the target has one, else libm's function); `clamp`, `pi` and `e`.
- `Random` (`Numerics`, a new namespace open everywhere): PCG32, so a seed gives the same numbers
  on every target, a chip's included: `create`, `nextU32`, `nextInt` (unbiased), `nextFloat`,
  `nextBytes` and `shuffle`; `Random.shared ()`, seeded from the operating system (Std).
- A chip's and WebAssembly's runtime has `pow`, `atan2` and `roundeven` (fdlibm's, weak), which
  compiler-rt lacks; `tests/libm.sh` checks them against the host's libm.
- `List.init` calls its function in index order, as F#'s (it went from the last index down).
- F#'s other collection functions (S2): `groupBy`, `countBy`, `chunkBySize`, `windowed`,
  `pairwise`, `scan` and `foldBack` on lists and arrays, `Array.tryFindIndex` and
  `Array.binarySearch`, `Map.change`, `Set.isSubset` and `isSuperset`; and `Queue`, `Stack` and
  `PriorityQueue` (lowest priority first, a leftist heap), values like lists.
- `Text.Utf8` (S4): `validate` (the offset of the first malformed byte), `decode` (malformed
  bytes as U+FFFD), `tryDecode` and `encodeChar`, Z# over spans, so on a chip too.
- A function that takes an array from a record parameter into a `let mutable` and writes it in
  place owns the record, so a unique array is changed in place (the record was borrowed, the
  caller's reference stayed, and every call copied the array: quadratic once inside a `while`).
- The runtime's threads (the pool's workers, the event loop, helpers) have 8 MB stacks, as Linux
  gives and as the main thread has: on macOS they had 512 KB, which deep recursion ran out of.

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
