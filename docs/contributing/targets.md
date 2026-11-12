# Targets and boards

How Z# is built for a platform, and what adding a board, a chip or an operating system takes.
The design is [DESIGN §10](../../DESIGN.md#10-targets); the plans are proposals
[0022](../proposals/0022-targets-macos-windows.md) (macOS and Windows) and
[0027](../proposals/0027-more-microcontrollers.md) (more microcontrollers).

## How a build reaches a target

- **clang** compiles the program's LLVM IR for the target.
- **`zig cc`** builds the C runtime and links, with Zig's bundled C libraries, so a cross build
  needs no SDK or sysroot.
- **The runtime** is one of two C files: `runtime/rt.c` for a host with an operating system,
  `runtime/rt-embedded.c` for a chip or freestanding WebAssembly (no OS, no libc).
- **The library** is Core everywhere, plus Std on a host.

| Kind | Targets | Runs in the suite |
|---|---|---|
| hosts | Linux x86-64 and arm64; macOS arm64 and x86-64; Windows x64 and arm64 (mingw-w64) | natively on CI's six runners; cross under qemu-user and Wine |
| chips | `cortex-m4` (M4F), `cortex-m0plus`; the board `nucleo-f401` | under QEMU |
| WebAssembly | `wasm32`, freestanding | under Node (`runtime/run-wasm.mjs`) |

## Adding a board (a chip already supported)

A target is a row found by name (`Options.mcus` in `src/`): the core's flags, the board's
memory map and interrupt lines, how its output leaves (semihosting or RTT), the command that
runs an image, and the heap's size.

1. **`runtime/boards/<board>.ld`:** the memory map (flash and RAM origins and sizes). The shared
   `cortex-m.ld` lays out the sections: the stack at the bottom of RAM so an overflow faults
   instead of overwriting.
2. **`runtime/boards/<board>.irq`:** the interrupt lines by name, so `[<Interrupt "USART2">]`
   works.
3. **The row** in `Options.mcus`: the name users pass to `--target`.
4. **Tests:** its programs under QEMU where QEMU has the board or one with the same memory map
   (the Nucleo's image boots on QEMU's STM32F405); a line in the guide's
   [microcontrollers chapter](../guide/11-microcontrollers.md).
5. **Say what was verified.** "Runs under QEMU" and "runs on the board" are different claims;
   the README's status section and proposal 0027 record which is true.

Registers come from the chip's SVD file through the `svd` type provider; don't write them by
hand.

## Adding a core or an architecture

Beyond a board:

- **The C ABI:** how structs are passed and returned by value, for `extern`, `import c` and
  `[<Export>]`. Each convention has tests in `tests/cimport/` and `tests/cexport/`.
- **`int`'s width:** 32 bits on a 32-bit target. Library code that assumes 64 fails here first;
  Core's tests run on both chips and wasm32 for that reason.
- **What LLVM can't do there:** the Cortex-M0+ and WebAssembly can't lower Z#'s tail calls at
  `-O0`, so `-g` alone stays an optimized build on them.
- **The runtime's port:** startup, the heap, the event loop's timer, output and exit, the stack
  guard, and atomics where the core has none.
- **SIMD:** a module per architecture (`Simd.X86`, `Simd.Arm`), with the portable `Simd` on
  every target.

## Adding an operating system

- **`rt.c`:** files, processes, sockets, the event loop (epoll, kqueue, or wepoll on Windows),
  threads.
- **Std's behavior is one behavior.** Where a system differs by design (a path's separator), the
  guide and the tests say so (`x.windows.out`); elsewhere the library hides the difference.
- **The toolchain:** which clang, how `zig cc` links, what `zs doctor` must find.
- **A release archive:** the target in `src/release.sh`'s list.
- **A CI runner:** a row in the workflow's matrix that unpacks the archive and runs the suite,
  the bootstrap included ([CI and releases](release.md#ci)). A platform without a runner isn't
  supported, whatever builds.

## Rules

- **Core stays free of the operating system.** A function that needs one belongs in Std, and a
  chip build that reaches Std is a compile error naming it.
- **`rt-embedded.c` allocates only from its static heap,** masks interrupts while the heap
  changes, and links nothing a program doesn't use (a program without tasks carries no event
  loop).
- **Cross builds are reproducible from any host:** the same bytes whichever machine builds them.
- **Behavior that differs by target is documented as target-dependent** in the specification:
  `int`'s width, the library tier, C's layout and calling convention. Nothing else may differ.
