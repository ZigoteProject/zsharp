# Proposal 0027: more microcontrollers: chips and boards as data, real hardware, RISC-V

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | a design review, before phase 12's M4 (one real board) is built, since M4 is the first item that needs the split this proposal makes |
| **Builds** | track M, items 4 (more boards) and 5 (RISC-V); the flagship's board (phase 12, the Nucleo-F401RE) |
| **Rests on** | decisions 26 (cross-compilation through `zig cc`), 29 (target order), 42 (`[<NoAlloc>]`), 60 (interrupt handlers) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §10](../../DESIGN.md#10-targets) (tiers, bare metal), [§11](../../DESIGN.md#11-c-interop) (the C ABI) |
| **Related** | [0012 interrupts, `[<NoAlloc>]` and intrinsics](0012-interrupts-noalloc-intrinsics.md) (the board's `.irq` table, `Cpu` per architecture), [0014 placement](0014-placement.md) (heap and stack per board, `.noinit`), [0016 async on bare metal](0016-async-bare-metal.md) (the clock per board), [0022 targets: macOS and Windows](0022-targets-macos-windows.md) (the hosted half of `--target`), [0001 type providers](0001-type-providers.md) (SVD), [0018 packages](0018-packages.md) (boards from packages) |

- [ ] Discussion
- [ ] Approved in principle
- [ ] Implementation

## Summary

Z# runs on two Cortex-M cores today, each tied to one QEMU machine: `cortex-m4` is QEMU's
`mps2-an386` and `cortex-m0plus` is QEMU's `microbit`. The core, the memory map, the boot
image, the output channel and the program that runs the image are one record
(`src/Build/Options.zs:6-14`), and four places assume the architecture is 32-bit Arm. This
proposal separates them and then fills the table:

```sh
zs build fw.zs --target nucleo-f401 -o fw.elf      # a board: its core, memory map, boot, runner
zs run   fw.zs --target nucleo-f401                # flashes through probe-rs, output over RTT
zs run   fw.zs --target cortex-m7                  # a core alone: its QEMU machine (mps2-an500)
zs build fw.zs --target rp2040 -o fw.uf2           # the Pico: boot2 prepended, UF2 out
zs run   fw.zs --target riscv32imac                # RISC-V under QEMU's virt, semihosting
zs build fw.zs --target esp32c3 -o fw.bin          # an ESP32-C3, direct boot
```

1. **Generalize** (no new chip yet): the machine word from the triple's architecture, a *core*
   and a *board* as two records, a linker layout and a runner per architecture. This also fixes
   a 32-bit Arm Linux build that links a 64-bit-word program against a 32-bit-word runtime today
   (*Blockers*, B1).
2. **More Arm cores under QEMU, for free:** Cortex-M3, M7 and M33 are a table row and a linker
   script each; QEMU 11 has a machine for each.
3. **Real boards:** the Nucleo-F401RE first (the flagship), then the Raspberry Pi Pico and Pico 2
   (RP2040, RP2350) and an nRF52840 board. A real board needs an output channel that isn't
   semihosting (RTT) and a runner that flashes (probe-rs).
4. **RISC-V:** `rv32imac` under QEMU's `virt` first (the C ABI, the runtime's port, the
   benchmarks), then the ESP32-C3 and C6 on hardware.

**Not here:** Xtensa (the original ESP32, S2, S3: no backend in the LLVM or the Zig the build
uses), AVR and MSP430 (16-bit pointers; Z#'s `int` is the machine word), Cortex-A bare metal.
*Alternatives* says why for each.

## Motivation

- **The flagship is a real board** (phase 12, status 2026-10-26: an ST Nucleo-F401RE) and Z#
  can't run on it. `examples/mcu/nucleo-f401.zs:9-11` says so: "Not flashable yet: cortex-m4
  links for QEMU's mps2-an386 memory map". Its flash starts at `0x08000000`, not `0`, and its RAM
  is 96 KB, not 4 MB. Worse, `println` on real hardware without a debugger attached is a
  `bkpt 0xab` (`runtime/rt-embedded.c:437-443`), which escalates to a HardFault, whose handler
  panics, which prints, which faults again: the board locks up on its first line of output.
- **The chips people buy.** The boards a newcomer has on their desk are a Pico (RP2040, an M0+,
  the cheapest), an ESP32 (now mostly C3 or C6 for new designs, both RISC-V), a Nucleo or Black
  Pill (STM32F4), a micro:bit v2 or nRF52840 dongle. Z# has the M0+ and the M4F *cores* for
  three of these and boots on none of them.
- **RISC-V** has been track M item 5 since the first part of the track, and DESIGN §10 names
  the ESP32-C3. Nothing in the compiler knows the architecture, and it doesn't fail cleanly:
  it picks x86-64's C ABI and a 64-bit word (B1, B2).
- **Without this:** the C-firmware path (M6, `zs build --lib --target cortex-m4`) works on any
  Cortex-M4: the vendor's SDK has the startup, the linker script and the flashing, and Z# is an
  archive. It's the right answer for a program that is mostly vendor drivers, and stays one.
  But it makes Z# a guest in a C project, which isn't the "firmware in Z#" the flagship is for,
  and it doesn't exist at all for RISC-V (B1-B3).

## Where things stand

### The pipeline for a chip

| Step | What runs | Where | Arm-specific |
|---|---|---|---|
| Check | the checker with the chip's word size (Std not loaded) | `src/Build/Check.zs:180`, `Types.Repr.wordBytes` | **yes:** `wordBytes` is 4 only for `thumb*` and `wasm32*` (`src/Types/Repr.zs:142`) |
| `import c` | clang with `--target=<triple> -ffreestanding -nostdlibinc` and the chip's flags | `src/Build/Modules.zs:165-173` | no; the chip is found by triple |
| Codegen | LLVM IR, `i32` words, the C ABI by architecture | `src/Gen/Layout.zs:166-182`, `:470-530`, `:567-570` | **yes:** `abiFor` knows aarch64, arm/thumb, Windows, wasm; anything else gets System V x86-64 |
| Compile | `clang --target=<triple> <cflags> -c program.ll` | `src/Build/Compile.zs:307` | no |
| Runtime + link | `zig cc -target <zigTarget> -mcpu=<zigCpu> -T <script> program.o rt-embedded.c` | `src/Build/Compile.zs:297-311` | **yes:** always splices `boards/cortex-m.ld` into the board's script (`:303-304`) |
| Runtime | vector table, reset, FPU, SysTick, semihosting, heap, exit report | `runtime/rt-embedded.c` | **yes:** inline Arm assembly and SCB/SysTick/DWT addresses (B3) |
| Run | `qemu-system-arm -M <board> -semihosting …` | `src/Commands.zs:106` | **yes:** the program is hardcoded |
| Benchmarks | `bench/mcu/run.sh`: Z# against C under `qemu-system-arm -icount` | `bench/mcu/run.sh:18-21` | yes |

### The targets

| `--target` | Core | Triple | Board (QEMU) | Heap | Tested |
|---|---|---|---|---|---|
| `cortex-m4` | Cortex-M4F | `thumbv7em-none-eabihf` | `mps2-an386` (4 MB / 4 MB) | 64 KB | QEMU in `./test.sh`, `bench/mcu` |
| `cortex-m0plus` | Cortex-M0+ | `thumbv6m-none-eabi` | `microbit` (256 KB / 16 KB) | 8 KB | QEMU in `./test.sh` |
| `wasm32` | none | `wasm32-unknown-unknown` | none (Node) | 1 MB | Node in `./test.sh` |

### The dependencies and what they support

Measured on the development machine (2026-10-27); the CI container pins its own versions.

| Dependency | Version | Role | Microcontroller architectures it has | Missing |
|---|---|---|---|---|
| clang / LLVM | 23.1 (Homebrew `llvm`) | compiles the program's IR | ARM/Thumb (all Cortex-M), RISC-V 32 and 64, AVR, MSP430 *(experimental)*, WebAssembly | **Xtensa** (not built by default; Espressif ships a fork) |
| `zig cc` | 0.17.0 (LLVM 22) | compiles `rt-embedded.c` and links (ld.lld) with compiler-rt | `thumb-freestanding-eabi[hf]` any `-mcpu=cortex_m*`, `riscv32-freestanding-none` with `-mcpu=generic_rv32+m+a+c…`, `avr-freestanding` | **Xtensa:** `No available targets are compatible with triple "xtensa-unknown-unknown-unknown"`; target names are Zig's: `riscv32-unknown-none-elf` is `UnknownOperatingSystem` |
| QEMU | 11.1 | runs tests and benchmarks | Arm: `mps2-an385` (M3), `mps2-an386` (M4), `mps2-an500` (M7), `mps2-an505`/`an521` (M33), `microbit` (nRF51, M0), `netduinoplus2` and `olimex-stm32-h405` (STM32F405, M4), `stm32vldiscovery` (M3). RISC-V 32: `virt`, `sifive_e`, `spike`, `opentitan` | **no RP2040/RP2350, no nRF52, no ESP32-C3/C6** upstream (Espressif's QEMU fork has the C3); Xtensa: only Tensilica's dev boards |
| Node | 24 | runs `wasm32` | | |
| `llvm-ar`, `llvm-size` | 23.1 | `--lib` archives, `bench/mcu`'s sizes | any | |
| probe-rs | *not installed* | flashing and RTT (proposed) | every Cortex-M, RISC-V incl. ESP32-C3/C6 over their built-in USB-JTAG, RP2040/RP2350 over a debug probe | Xtensa (partial) |
| picotool / UF2 | *not installed* | the Pico without a probe (optional) | RP2040, RP2350 | |

Checked by compiling, not read from documentation: the IR of `examples/simple.zs` built for
`cortex-m4` recompiles with `clang --target=riscv32-unknown-none-elf -march=rv32imc` and with
`--target=avr` unchanged (it has no target triple or data layout of its own); `rt-embedded.c`
compiles for `cortex_m33` and `cortex_m7` unchanged, and fails for RISC-V (B3).

## Blockers

Ranked by what they stop. Each has its evidence; each is fixed by a step in *Order of
implementation*.

| # | Blocker | Evidence | Stops |
|---|---|---|---|
| B1 | **The word size is by name prefix.** `wordBytes` is 4 for `thumb*` and `wasm32*` and 8 for everything else, while `isArm32` also matches `arm*` (`src/Gen/Layout.zs:470`) | `zs build --target arm-linux-musleabihf --emit-llvm` declares `@zs_alloc(i64)`; `rt.c:190` defines it with `zs_int` = `intptr_t` = 32 bits. It links and is wrong (object headers, lengths, counts). `riscv32*` gets the same 8 | RISC-V; it's a live bug for 32-bit Arm Linux |
| B2 | **No RISC-V C ABI.** `abiFor` falls through to x86-64 System V's eightbytes (`src/Gen/Layout.zs:495-530`), and `byval` gives `ptr byval` (`:567-570`) | ILP32 passes a struct of up to 2×XLEN in integer registers, larger ones by a pointer to a caller's copy (not `byval`); ILP32F/D put a struct of one or two floats, or a float and an integer, in float registers | `[<CLayout>]` structs by value, `--lib`, callbacks on RISC-V |
| B3 | **The runtime is Arm assembly outside the WebAssembly branch.** Semihosting is `bkpt 0xab` with `r0`/`r1` (`rt-embedded.c:437-443`); `context()` reads `ipsr` (`:1036-1044`); `Reset_Handler` writes CPACR and SysTick and reads `sp` (`:1188-1209`); the vector table is the ARMv7-M one (`:1227-1229`); `--lib`'s ticks are the DWT (`:1145-1162`) | `zig cc -target riscv32-freestanding-none` fails with `unknown register name 'r0'` and `unrecognized instruction mnemonic: mrs a1, ipsr`; with `-DZS_LIB` too (`context()` is shared) | RISC-V, both as a program and as a library |
| B4 | **Semihosting is the only output, and it faults without a debugger.** `bkpt` with no debugger attached is a HardFault on ARMv7-M and a lockup on ARMv6-M; the fault handler panics, which prints | `fault()` → `zs_panic_c` → `write_bytes` → `semihost` (`rt-embedded.c:1211`, `:445`) | every real board: the first `println` hangs it |
| B5 | **One record is the core, the memory map and the QEMU machine.** `Mcu.board` is both the QEMU `-M` name and the linker script's file name (`Options.zs:6`, `Compile.zs:304`, `Commands.zs:106`) | a Nucleo-F401 build would need a QEMU machine named `nucleo-f401`, which doesn't exist | every real board |
| B6 | **Targets are found by triple.** `targetName` and `Modules.targetFlags` look the chip up by `(snd c).triple = target` (`Options.zs:130-135`, `Modules.zs:168`) | two boards with the M4F core share `thumbv7em-none-eabihf`: the first in the list wins, so `[target.nucleo-f401] heap` would read `[target.cortex-m4]`'s | more than one board per core |
| B7 | **The layout is Cortex-M's.** `cortex-m.ld` has `.vectors` first and `Reset_Handler` as the entry; the driver splices it into every board's script | RISC-V has no vector table at the start of flash (`mtvec` points at a trap entry), the RP2040 needs 256 bytes of boot2 before the vectors, the RP2350 an `IMAGE_DEF` block in the first 4 KB, the ESP32-C3 an image header (or direct boot's magic) | RP2040, RP2350, RISC-V, ESP32 |
| B8 | **The runner is QEMU's Arm binary.** `zs run` and `./test.sh` call `qemu-system-arm`; nothing flashes | `src/Commands.zs:106`, `test.sh:208-215` | `zs run` on a board; RISC-V tests |
| B9 | **Atomics on cores without them.** Counts on shared objects are `atomicrmw` (`src/Gen/Prelude.zs:275`, `:299`); the M0+ (ARMv6-M) and `rv32imc` (no A) have no atomic instructions, so LLVM calls `__atomic_*` | not reached today: bare metal has no threads, and handlers (0012) aren't built. Whether zig's compiler-rt gives a correct single-core `__atomic_fetch_add_4` for these cores is **unverified** | 0012's handlers sharing objects, on M0+ and RV32IMC |
| B10 | **FPU variants are per chip, and set twice.** The flags are in `cflags` for clang and in `zigCpu` for zig, and only the M4F's `fpv4-sp-d16` exists | the M7 has `fpv5-d16` (double precision), the M33 and RP2350 `fpv5-sp-d16`; a mismatch between the two compiles is a link error at best (`eabi` vs `eabihf`) and a wrong FPU at worst | the M7, M33 and RP2350 |

## Detailed design

### Cores and boards

`Options.Mcu` becomes two records. A *core* is what clang and zig need; a *board* is what the
linker script, the boot image and the runner need. Both stay F#-style list literals in
`Options.zs` (the board table is code until packages bring boards, *Unresolved questions* 4).

```fsharp
/// What the compilers are told: the triple, the flags (one list, for clang and for zig cc),
/// and the architecture's runtime port and linker layout.
type Core = { triple: string; zigTarget: string; zigCpu: string; cflags: list<string>; arch: Arch }
and Arch = ArmM | RiscV32 | Wasm

/// Where the image goes and how it runs.
type Board =
  { core: string            // a core's name
    script: string          // runtime/boards/<script>.ld: MEMORY and the board's own sections
    boot: Boot              // what the image starts with
    output: Output          // semihosting (QEMU, a debugger) or RTT (a probe)
    runner: Runner          // QEMU's machine, probe-rs's chip name, or none
    heap: int; stack: int }  // 0014's defaults, which [target.<name>] overrides
and Boot = Vectors | Rp2040Boot2 | Rp2350ImageDef | EspDirectBoot
and Output = Semihosting | Rtt
and Runner = Qemu of program: string * machine: string | ProbeRs of chip: string | NoRunner
```

`--target` takes a board's name or a core's. A core's name means its QEMU board, so
`cortex-m4` and `cortex-m0plus` mean what they mean today.

| `--target` | Core | Script | Boot | Output | Runner |
|---|---|---|---|---|---|
| `cortex-m0plus` | `thumbv6m-none-eabi`, `cortex_m0plus` | `microbit` | vectors | semihosting | `qemu-system-arm -M microbit` |
| `cortex-m3` | `thumbv7m-none-eabi`, `cortex_m3` | `mps2-an385` | vectors | semihosting | `qemu-system-arm -M mps2-an385` |
| `cortex-m4` | `thumbv7em-none-eabihf`, `cortex_m4+vfp4d16sp` | `mps2-an386` | vectors | semihosting | `qemu-system-arm -M mps2-an386` |
| `cortex-m7` | `thumbv7em-none-eabihf`, `cortex_m7+fp_armv8d16` | `mps2-an500` | vectors | semihosting | `qemu-system-arm -M mps2-an500` |
| `cortex-m33` | `thumbv8m.main-none-eabihf`, `cortex_m33` | `mps2-an505` | vectors | semihosting | `qemu-system-arm -M mps2-an505` |
| `riscv32imac` | `riscv32-unknown-none-elf`, `generic_rv32+m+a+c` | `qemu-virt-rv32` | vectors (trap entry) | semihosting | `qemu-system-riscv32 -M virt -bios none` |
| `nucleo-f401` | `cortex-m4` | `stm32f401re` (512K @ `0x08000000`, 96K @ `0x20000000`) | vectors | RTT | `probe-rs run --chip STM32F401RETx` |
| `rp2040` | `cortex-m0plus` | `rp2040` (2M @ `0x10000000`, 264K @ `0x20000000`) | boot2 | RTT | `probe-rs run --chip RP2040` |
| `rp2350` | `cortex-m33` | `rp2350` (4M @ `0x10000000`, 520K @ `0x20000000`) | `IMAGE_DEF` | RTT | `probe-rs run --chip RP235x` |
| `nrf52840` | `cortex-m4` | `nrf52840` (1M @ `0`, 256K @ `0x20000000`) | vectors | RTT | `probe-rs run --chip nRF52840_xxAA` |
| `esp32c3` | `riscv32-unknown-none-elf`, `generic_rv32+m+c` | `esp32c3` | direct boot | RTT | `probe-rs run --chip esp32c3` |
| `esp32c6` | `riscv32-unknown-none-elf`, `generic_rv32+m+a+c` | `esp32c6` | direct boot | RTT | `probe-rs run --chip esp32c6` |
| `wasm32` | `wasm32-unknown-unknown` | none | none | host imports | `node run-wasm.mjs` |

- **Lookups are by name, never by triple** (B6): `Options` keeps the board's name next to its
  triple, and `targetName`, `Modules.targetFlags` and the `[target.<name>]` lookup use it.
- **The flags are one list** (B10): `-mcpu`/`-mfpu`/`-mfloat-abi` are written once, and the
  driver passes `zigCpu` to zig and `cflags` to clang from the same row; a test builds every row
  and checks that the program's object and the runtime's agree on `Tag_ABI_VFP_args`
  (`llvm-readelf -A`).
- **The word size comes from the architecture** (B1): `wordBytes` is 4 for `thumb*`, `arm*`,
  `riscv32*`, `wasm32*`, `i386`/`i686`/`x86` and 8 otherwise, in one function
  `Types.Repr.wordBytes` that `Gen.Layout.is32` already calls. `arm-linux-musleabihf` then
  builds correctly, a fix with no other cost.

### The RISC-V C ABI (B2)

`abiRiscV32` next to `abiArm32`, as clang lowers ILP32 and ILP32F (`riscv32imac` and the
ESP32s have no FPU, so ILP32; ILP32F is in the table for a later chip with F):

| Rule (ILP32) | In `Codegen` |
|---|---|
| a struct of up to 8 bytes passes in one or two integer registers, as integers | `Pieces [ "i32" ]` or `[ "[2 x i32]" ]` (`"i64"` when it's 8-byte aligned) |
| a larger struct passes by a pointer to a copy the caller made | `Memory`, and `byval` returns `ptr` (as arm64 and Windows do), not `ptr byval` |
| a struct of up to 8 bytes returns in `a0`/`a1`; a larger one through an sret pointer | `cRet`: `iN` or `[2 x i32]`, else sret |
| ILP32F: a struct of one float, two floats, or a float and an integer of up to 4 bytes goes in float registers (and an integer one) while they last | `Pieces [ "float"; "i32" ]` etc., only on an `f` ABI; not built until a chip with F is in the table |
| eight argument registers (`a0`-`a7`), then the stack | LLVM, from the pieces |

`tests/cimport/abi.zs` and `tests/cexport/bare.c` run on `riscv32imac` under QEMU, as they run
on both Arm cores today; they're what tells a guess from clang's lowering.

### The runtime's ports (B3, B4)

One file stays one file: `rt-embedded.c` gets an `#if defined(__riscv)` section beside the Arm
one, and the shared part (heap, strings, numbers, panics) is untouched. Each row is a few lines
of C:

| Piece | Cortex-M (today) | RISC-V |
|---|---|---|
| startup | vector table at flash start, `Reset_Handler` | `_start` in `.text.init`: `la sp, _estack`, `la gp, __global_pointer$`, `csrw mtvec, trap_entry`, then the same copy and zero |
| FPU | CPACR under `__ARM_FP` | `mstatus.FS` under `__riscv_flen` (none of the proposed chips) |
| ticks | SysTick, wraps counted | `rdcycle`/`rdcycleh` (`mcycle`) on `virt` and the C6; the C3 has no standard cycle CSR (its counter is Espressif's `mpccr`, per its TRM), so the board's row picks the systimer there |
| context (for callbacks, 0012's handlers) | `ipsr` | a `volatile` trap depth the trap entry increments, 0 in thread mode |
| exit, output on QEMU | semihosting `bkpt 0xab` | RISC-V semihosting: `slli x0,x0,0x1f; ebreak; srai x0,x0,7` with `a0`/`a1`, which QEMU's `-semihosting` takes |
| faults | `fault()` → panic | the trap entry → `zs_panic_c` naming `mcause` and `mepc` |
| watchdogs | none at reset on the proposed Arm boards | the ESP32-C3/C6's RTC and timer-group watchdogs are armed by the ROM: disabled in `_start` behind `ZS_BOARD_ESP` |

**Output on a real board (B4) is RTT:** a control block (`"SEGGER RTT"`, one up buffer of 1 KB
by default) in `.bss`, written by `write_bytes` without blocking; probe-rs (or any J-Link or
OpenOCD) finds it by its ID and reads it over SWD or JTAG while the core runs. Nothing to wire,
no UART pins taken, no clocks to set. Exit on a real board: the report line, then
`bkpt 0xab` with `SYS_EXIT_EXTENDED` **only when a debugger is attached** (DHCSR's
`C_DEBUGEN`, `0xE000EDF0` bit 0, which `probe-rs run` sets and turns into its own exit code);
without one, the core sleeps in a `wfi` loop. A fault does the same: the message goes into RTT,
and nothing executes a `bkpt` that would fault again. `ZS_OUTPUT_RTT` selects this at the
runtime's compile, from the board's `output`.

A `uart` output is not proposed: it needs clocks and pins per board, which is the program's
business (`examples/mcu/uart.zs` already does it in Z#).

### Linker layouts and boot images (B7)

`runtime/boards/` keeps a `MEMORY` file per board and gains one layout per architecture:
`cortex-m.ld` (today's) and `riscv.ld` (`.text.init` first, `__global_pointer$`, the same
`.data`/`.bss`/stack symbols, so `Reset_Handler`'s copy loop and the stack report are shared).
The driver splices the board's layout by `Core.arch` where it splices `cortex-m.ld` today
(`src/Build/Compile.zs:303-304`).

| Boot | What the board's script adds | Where its bytes come from |
|---|---|---|
| vectors | nothing | |
| RP2040 boot2 | `.boot2` (256 bytes) at `0x10000000`, vectors at `0x10000100` | `runtime/boards/rp2040-boot2.S`: the generic `w25q080` second stage from the Pico SDK (BSD-3-Clause), its CRC computed and checked by the board's test; `zs build -o x.uf2` writes UF2 directly (a 30-line writer: 256-byte payloads in 512-byte blocks) so a Pico flashes by drag and drop |
| RP2350 `IMAGE_DEF` | a 20-byte block in `.start_block` within the first 4 KB | written as data in `rt-embedded.c` behind `ZS_BOARD_RP2350`; the boot ROM needs nothing else for an Arm image |
| ESP direct boot | the magic word `0xaedb041d` twice at the start of the flash image, `_start` after it | the ROM of the C3 (from ECO3) and the C6 jumps to it with the flash cache mapped; `zs build -o x.bin` writes the flat image espflash or probe-rs writes to offset 0 |

### Running and flashing (B8)

`zs run` uses the board's runner: `Qemu (program, machine)` replaces the hardcoded
`qemu-system-arm` (`src/Commands.zs:106`), and `ProbeRs chip` runs
`probe-rs run --chip <chip> <elf>`, which flashes, streams RTT to the terminal and returns the
program's exit code. A missing tool is one line: `zs run --target nucleo-f401 needs probe-rs
(https://probe.rs); or zs build -o fw.elf and flash it your way`. `zs build` never needs it.

probe-rs is the one new external tool, chosen because it covers every proposed board, Arm and
RISC-V, with one CLI, and because its RTT and exit-code handling are what `zs run` needs;
OpenOCD would need a config per board and a GDB for exit codes.

### Tests

| What | Where | Runs in CI |
|---|---|---|
| every target row builds `examples/simple.zs` and `tests/mcu/*.zs`, and the FPU attributes agree | `./test.sh` | yes |
| `tests/mcu/*`, `tests/cimport/abi.zs`, `tests/cexport/bare.c`, the libm check, on `cortex-m3`, `m7`, `m33` and `riscv32imac` | `./test.sh`, QEMU | yes |
| `bench/mcu` on `cortex-m4` (ratios kept) and `riscv32imac` (reported: `-icount` on `virt`), against C built with the same `zig cc` | `bench/mcu/run.sh <target>` | yes |
| `examples/mcu/nucleo-f401.zs` blinks, answers `status` over its UART, prints over RTT | by hand, on the board | no |
| a Pico blinks from a UF2 copied to its drive; an ESP32-C3 blinks and prints over its USB-JTAG | by hand | no |

### Order of implementation

1. **Generalize** (B1, B5, B6, B7's driver part, B8's runner part, B10): `wordBytes` from the
   architecture; `Core` and `Board`; lookups by name; `Runner`. No new target; every existing
   test unchanged, plus `arm-linux-musleabihf` building with 32-bit words.
2. **Cortex-M3, M7, M33 under QEMU:** a row and a `MEMORY` file each; the suite on each.
3. **RTT and the nucleo-f401 board** (B4): the flagship runs (phase 12's M4). Interrupts
   (0012) then land on a board that has a real `.irq` table.
4. **RISC-V under QEMU** (B2, B3, B7's `riscv.ld`): `riscv32imac` with the ABI tests and
   `bench/mcu`. B9 is settled here: a test increments a shared count from a trap and from thread
   mode on `rv32imc` and on the M0+.
5. **The Pico and Pico 2** (boot2, `IMAGE_DEF`, UF2), **nRF52840** (a `MEMORY` file).
6. **ESP32-C3 and C6** (direct boot, watchdogs, the systimer for ticks on the C3).

Steps 1-3 are what phase 12 needs; 4-6 are track M items 4 and 5, after it.

## Drawbacks

- **The matrix grows:** from two QEMU targets to six in CI. Each QEMU run of `tests/mcu` is
  seconds, so the cost is in the build step (each row compiles the runtime), not the runs.
- **Hardware isn't in CI.** A board's boot bytes (boot2, `IMAGE_DEF`, direct boot) are checked
  by a test of the image's bytes and by hand, not by running. A regression in them shows up as
  a board that doesn't boot.
- **A vendored binary-ish file:** RP2040's boot2 is assembly from the Pico SDK with a checksum,
  and it's specific to the flash chip (`w25q080` covers the Pico and most clones; a board with
  other flash needs its own).
- **probe-rs** is a Rust tool the user installs; `zs build` doesn't need it, `zs run` on a board
  does.
- **Boards as code:** adding a board is a compiler change until boards come from packages.

## Alternatives

- **Startup and vector table generated by the compiler** (TinyGo, Embassy's `cortex-m-rt`):
  the compiler would own every chip's layout. 0012 declined it for the same reason: the weak
  defaults in the runtime and the linker's `KEEP` do it with no code in the compiler.
- **A board file format** (`runtime/boards/nucleo-f401.toml`) instead of a table in
  `Options.zs`: right once boards come from packages (0018) or from `zs.toml`; until then it's a
  parser and a schema for a dozen rows.
- **Vendor SDKs only** (pico-sdk, ESP-IDF, STM32Cube, nRF Connect) through `--lib`: works for
  Arm today and stays the path for a program that's mostly vendor drivers (Wi-Fi on an ESP32,
  BLE on an nRF). It isn't firmware in Z#, and it needs B1-B3 for RISC-V anyway.
- **Xtensa (ESP32, S2, S3):** LLVM's Xtensa backend is experimental upstream and not in the
  Homebrew or Zig builds (`zig cc -target xtensa-…` fails, `llc --version` doesn't list it); the
  working toolchain is Espressif's LLVM fork. Supporting it means a second clang, and a runtime
  built by that clang instead of `zig cc` (decision 26's path). Deferred until Zig ships the
  backend; new Espressif designs are RISC-V (C2, C3, C5, C6, H2, P4).
- **AVR (Arduino Uno) and MSP430:** 16-bit pointers and `intptr_t`, so Z#'s `int` (the machine
  word, decision of track M's first part) would be 16 bits, and 2 KB of RAM holds little of a
  reference-counted heap. LLVM and zig both have AVR, so it's possible; it changes what `int`
  means. Declined: the Uno's niche is served by the Pico at the same price.
- **UART as the default output on boards:** needs clocks and pins per board; RTT needs only the
  debug link the flashing already uses.
- **OpenOCD instead of probe-rs:** a config file per board and GDB for the exit code; probe-rs
  is one command for every proposed board.
- **Espressif's QEMU fork for the ESP32-C3 in CI:** a second QEMU to build and pin; `virt` tests
  the architecture, and the board-specific part (direct boot, watchdogs) is small.

## Compatibility

- **Not breaking.** `--target cortex-m4`, `cortex-m0plus` and `wasm32` mean what they mean, with
  the same QEMU machines, heaps and output; `[target.cortex-m4]` keeps working.
- **`arm-linux-*` and other 32-bit hosted targets change ABI:** their programs now use 32-bit
  words, matching their runtime. Anything built for them before was wrong, so nothing correct
  breaks.
- **An older compiler** given `--target nucleo-f401` passes it to zig as a triple and fails with
  zig's `unable to parse target query`; given `[target.nucleo-f401]` it accepts the section and
  ignores it, as it ignores any target it doesn't build for.
- **The library:** no change. `Mmio`, `Runtime.ticks` and (0012) `Cpu` have the same surface;
  `Cpu.wfe`/`sev` are absent on RISC-V, as 0012's table says.

## Pragmatics

- **Diagnostics:**

  | Situation | Message |
  |---|---|
  | an unknown target | `zs: unknown target 'stm32f4'; the chips are cortex-m0plus, cortex-m3, …; the boards are nucleo-f401, rp2040, …; or a triple (aarch64-linux-musl)` |
  | a known-but-unsupported family | `zs: esp32s3 is Xtensa, which the LLVM zs uses has no backend for; the RISC-V ESP32s are esp32c3 and esp32c6` |
  | a runner that isn't installed | `zs run --target nucleo-f401 needs probe-rs (https://probe.rs); zs build -o fw.elf builds it without` |
  | probe-rs finds no probe | probe-rs's own message, then `is the board plugged in, and its ST-Link's firmware current?` |
  | the image doesn't fit | 0014's message, with the board's name and its flash and RAM |

- **Tooling:** `zs lsp` reads `target` from `zs.toml`, so a project for `nucleo-f401` gets the
  32-bit word and no Std while editing, as `cortex-m4` does today. `zs build --time` on a board
  prints flash and RAM use against the board's sizes (0014).
- **Performance:** nothing changes on existing targets. RISC-V's numbers come from `bench/mcu`
  against C with the same compiler; the expectation is Arm's ratios, since everything that made
  them (borrowing, fusion, unboxing) is above LLVM.
- **Scaling:** a board is about 20 lines (a row and a `MEMORY` file); an architecture is a
  runtime section (about 150 lines), a layout and an ABI function.
- **Culture-aware formatting:** none involved.

## Unresolved questions

1. **Names:** `nucleo-f401` (the board) or `stm32f401re` (the chip) as the target? A chip has
   one memory map and many boards; the board adds the probe and its LEDs. This proposal names
   boards where the board matters for flashing and output (`nucleo-f401`, `rp2040` meaning the
   Pico) and chips otherwise.
2. **B9:** whether zig's compiler-rt `__atomic_*` on ARMv6-M and RV32IMC is correct against an
   interrupt on one core, or the runtime defines them with interrupts masked (`cpsid i`,
   `csrci mstatus, 8`). Settled by step 4's test, before 0012's handlers share objects.
3. **The ESP32-C3's ticks:** the systimer (16 MHz, 52-bit, standard across C3/C6) or
   Espressif's `mpccr` cycle counter. The systimer matches 0016's need for a time base.
4. **Boards from outside:** a `[board.<name>]` section in `zs.toml` (core, flash and RAM
   regions, runner) for a custom PCB, or boards as packages (0018). Both need the table above to
   become data; neither is needed for the boards listed.
5. **RTT buffer size and blocking:** 1 KB, dropping output when full (as today's `--lib`
   default drops it), or blocking until the host reads (which hangs a board with no probe
   attached).
6. **The C runtime's choice on RISC-V `--lib`:** an ESP-IDF or a vendor SDK has its own trap
   handler and C library; whether `context()` there comes from `mcause` or from a hook the
   firmware calls.

## History

- 2026-10-27: drafted from an inventory of the compiler, the runtime and the toolchain on the
  development machine (LLVM 23.1, Zig 0.17.0, QEMU 11.1): the blockers above were reproduced, not
  read; B1 was found as a live bug for `arm-linux-musleabihf` along the way.
