# Proposal 0022: targets: macOS arm64 and Windows x64

| | |
|---|---|
| **Status** | Approved in principle (decision 29). Reordered on 2026-10-24: macOS arm64 and x86-64, Windows x64 and arm64, and the compiler on Linux arm64 are phase 11.5, before 0.1; this proposal's decisions carry to the three it doesn't name |
| **Decided at** | decision 29 ([DESIGN §13](../../DESIGN.md#13-decisions)); track T's plan ([ROADMAP](../../ROADMAP.md#more-targets-t)); phase 12's "macOS arm64" item ([ROADMAP](../../ROADMAP.md#phase-12-release-062)). The unresolved questions are settled as each target's implementation starts |
| **Builds** | track T, items 1 (macOS) and 2 (Windows) |
| **Rests on** | decisions 5 (panics), 26 (cross-compilation through `zig cc`), 29 (target order), 48 (a loop per thread) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §6](../../DESIGN.md#6-concurrency-task) (the loop), [§10](../../DESIGN.md#10-targets) (tiers), [§11](../../DESIGN.md#11-c-interop) (the C ABI) |
| **Related** | [0011 debug info, profiles and traces](0011-debug-info-profiles-traces.md) (lldb, DAP), [0008 threads](0008-threads.md) (the pool on other OSes), [0024 library API](0024-library-api.md) (`Path` on POSIX, processes), [0018 packages](0018-packages.md) (C dependencies per target), [0014 placement](0014-placement.md) (the per-target manifest table) |

- [x] Approved in principle
- [x] Discussion
- [x] Implementation (phase 11.5, decision 82: built for every target, Windows's suite run under Wine; CI on the platforms' runners next)

## Summary

Two more targets through the path `aarch64-linux-musl` takes today: clang compiles the
program's IR with `--target=`, and `zig cc` compiles `rt.c` and links against Zig's bundled C
library, so no SDK or sysroot is installed (decision 26).

```sh
zs build app.zs --target aarch64-macos -o app             # Mach-O, ad-hoc signed, runs on an M-series Mac
zs build app.zs --target x86_64-windows-gnu -o app.exe    # PE, mingw-w64's CRT, runs on Windows 10 and later
```

- **macOS arm64:** Apple's arm64 calling convention in `Codegen`, kqueue behind the loop's interface in `rt.c`, a kernel wait for `Mutex`, `sysctl` for CPU features, backtraces from libSystem. Native builds on a Mac too, which fixes the host-detection gap that makes a native build on any aarch64 host use x86-64's struct rules. Phase 12 runs the whole suite on GitHub's arm64 macOS runners.
- **Windows x64:** the Microsoft x64 convention in `Codegen`, and `rt.c` ported off POSIX in one `#ifdef _WIN32` block: wepoll (epoll's API over IOCP, one MIT C file) so the loop keeps its shape, `WaitOnAddress` for `Mutex`, Win32 threads, files, directories, processes and sockets behind the same `Native` functions, a UTF-8 console, and backslashes and drives in `Path`. Build-only until a Windows machine runs the suite: `./test.sh --target x86_64-windows-gnu --build-only` cross-compiles every test program.

No syntax changes, nothing in Core changes, and Std's surface is the same on every OS.

## Motivation

- **Many programmers' machine is a Mac** (phase 12's words). Without the target, a newcomer's five-minute hello world ([ROADMAP](../../ROADMAP.md#phase-12-release-062)'s first exit test) is impossible on macOS, and the release archive per target has one target.
- **A library used from C** (decision 30: the first audience) is used from C on whatever OS the host program runs on. `zs build --lib` that gives a `.a` for Linux only is a Linux library.
- **Microcontroller firmware** (the likely flagship niche) is written on Macs and Windows machines as much as on Linux: the host compiler must run there, and the chip builds already go through `zig cc`.
- **What the alternative looks like without this:** WSL or a Linux VM for Windows users, and Docker on Macs. Both work for a Linux binary and neither gives a native one, so a CLI tool written in Z# can't be shipped to the two desktops most people use.
- **What the code already assumes:** `rt.c` includes `sys/epoll.h`, `linux/futex.h`, `spawn.h`, `dirent.h` and `sys/auxv.h` (facts sheet §7; `runtime/rt.c:997-1003`, `2044-2046`, `2222` in the main working tree). None of it is in a Windows CRT and three of them aren't on macOS. `Codegen` picks the ABI by `target.StartsWith "aarch64"` and `"thumb"` (`src/Codegen.fs:445-448`), nothing else.

## Detailed design

### Target names

| `--target` | clang's triple | `zig cc -target` | Object format | C library | Loop |
|---|---|---|---|---|---|
| `aarch64-macos` | `aarch64-apple-macos` | `aarch64-macos` | Mach-O | libSystem (Zig ships the stubs) | kqueue |
| `x86_64-windows-gnu` | `x86_64-windows-gnu` | `x86_64-windows-gnu` | PE/COFF | mingw-w64 over the UCRT | wepoll over IOCP |
| *(none, on a Mac)* | the host's | not used | Mach-O | the installed one | kqueue |

- **The name is Zig's,** as `aarch64-linux-musl` is today; the driver maps it to clang's spelling where the two differ, as it maps `cortex-m4` to `thumbv7em-none-eabihf` (`src/Main.fs:183-192`, main working tree).
- **The host triple is computed** when `--target` is absent: `RuntimeInformation.OSArchitecture` and `IsOSPlatform` give it (`src/Codegen.fs:3586` and `src/Driver.fs:1599` already do the arch half for intrinsics and `-march`), and `Codegen` classifies by that triple everywhere it classifies today. This closes the facts sheet's gap (§6): a native build has target `""`, so `isArm64 ()` is false on an aarch64 Linux host and `[<CLayout>]` structs cross by System V's rules.
- **`x86_64-macos`** (Intel Macs) falls out of the same code, with System V's ABI as on Linux; it's built but not in CI. Windows on arm64, WASM (DESIGN §10, tier 4) and io_uring (DESIGN §6) are non-goals here.
- **Output names:** a Windows build with no `-o` writes `build/<name>.exe`; `--lib` writes `.a` on both (a COFF archive on Windows, which mingw and MSVC link), and an output ending in `.dylib` or `.dll` is a shared library, as `.so` is (DESIGN §11).

### Apple's arm64 convention

Apple's PCS is AAPCS64 with three documented differences, and LLVM applies all three once the triple says `apple`:

| Difference | Who does it |
|---|---|
| variadic arguments go on the stack, 8 bytes each, never in registers (`extern printf : cstr -> ... -> c_int`) | LLVM, from the `...` in the call's prototype that `Codegen` writes already (`src/Codegen.fs:2243-2245`) |
| stack arguments are packed to their natural alignment, not padded to 8 bytes | LLVM, for the scalars and arrays `Codegen` hands it; `abiArm64` (`:698`) gives LLVM `[n x float]`, `[2 x i64]` and `iN` pieces, which it places by the target's rules |
| `char` is signed | `import c` maps `char` to `i8` already (`src/CImport.fs:59`), which is right here and on x86-64; Linux aarch64's unsigned `char` is the odd one, and only the sign of values past 127 differs |

So `Codegen`'s work is classification: `isApple ()` next to `isArm64 ()`, with structs by `abiArm64` (an HFA of up to four floats in float registers, up to 16 bytes in integer registers, larger ones by a pointer to a copy, which `byval` returns on arm64, `:770-772`). The register budget in `cModes` (6 integer and 8 SSE, System V's) isn't consulted on arm64 (`Pieces ps when isArm64 ()`), and stays so.

### The Microsoft x64 convention

One convention for every function, and nothing like System V's eightbyte classification:

| Rule | In `Codegen` |
|---|---|
| four argument slots (RCX, RDX, R8, R9, or XMM0-3), assigned by position whatever the type; the fifth argument and later go on the stack | `cModes` counts one budget of 4, not separate integer and SSE budgets; a `callback` takes two slots (the function pointer and the user data), an sret pointer the first |
| a struct of 1, 2, 4 or 8 bytes passes as an integer of that size | `abiWin64`: `Pieces [ "i8" ]`, `"i16"`, `"i32"`, `"i64"`; a `{ x: f32; y: f32 }` is an `i64`, not an HFA |
| any other struct passes by a pointer to a copy the caller made | `Memory`, and `byval` returns `ptr` (as on arm64), never `ptr byval` |
| a struct of 1, 2, 4 or 8 bytes returns in RAX; any other through a hidden pointer in RCX | `cRet`: `iN`, else sret, as `abiFor` does for `Memory` today (`:775-781`) |
| the caller reserves 32 bytes of shadow space; variadic floats are copied to the integer register too | LLVM, from the triple |

`import c` on this target maps `long` and `unsigned long` to `i32` and `u32` (LLP64), where Linux and macOS map them to `int` and `usize` (`src/CImport.fs:71-76`); `size_t`, `intptr_t` and pointers stay 64-bit. A header is read once per target, so the cache in `.zs-cache/cimport/` is keyed by the target's data model.

**Why `windows-gnu` and not `windows-msvc`:** Zig ships mingw-w64 and builds Windows binaries without Visual Studio, from any machine; MSVC's toolchain runs on Windows only, which rules out the cross build that makes this target testable from Linux. The calling convention is the same Microsoft x64 convention either way, Zig's mingw-w64 links the UCRT as MSVC does, and a `.a` or `.dll` built here is called from MSVC code as from any C. What differs is C++ (name mangling, exceptions, which Z# never exports) and the debug format (DWARF in the PE, not a PDB: *Tooling*).

### The runtime on macOS

Everything `rt.c` uses is POSIX except four things (facts sheet §7). Each is a block under `#ifdef __APPLE__`, behind the function the rest of the file calls today:

- **The loop: kqueue.** `epoll_create1` becomes `kqueue()`; `epoll_ctl` becomes a `kevent` change with `EVFILT_READ` or `EVFILT_WRITE` (one filter per direction, as the loop keeps one callback per direction per descriptor, `zs_loop_wait`, `:1125`); `epoll_wait` with the timer heap's timeout becomes `kevent` with a `timespec`. The inbox's wake pipe (`pipe2` is Linux; `pipe` plus `fcntl` here, `:1239`) is watched with `EVFILT_READ` like any descriptor. Timers stay the in-process heap (`:1193-1210`): `EVFILT_TIMER` would move them into the kernel for no gain, since the heap sets one timeout per wait. The loop's interface (`zs_loop_wait`, `unwait`, `timer`, `post`, `step`, `blocking`, `expect`, `fulfill`, `spawn`) doesn't change, so `lib/std/Threading/Task.zs` and the `Native.loop*` builtins don't either.
- **`Mutex`: `os_sync_wait_on_address`** and `os_sync_wake_by_address_any` (`<os/os_sync_wait_on_address.h>`, macOS 14.4 and later) are the futex's shape: wait while the word holds a value, wake one. On an older macOS the same two calls are `__ulock_wait` and `__ulock_wake`, private but stable, which libc++'s atomics and Rust's `std::sync::Mutex` use; the runtime takes `os_sync_*` when `__MAC_OS_X_VERSION_MIN_REQUIRED` allows and `__ulock_*` below. The fallback for neither is the spin and `sched_yield` already in the `#else` branch (`:2050`), which is correct and slow.
- **CPU features:** `sysctlbyname("hw.optional.arm.FEAT_DotProd", …)` and its siblings (`FEAT_AES`, `FEAT_SHA256`, `FEAT_LSE`, `FEAT_FP16`, `FEAT_I8MM`, `FEAT_BF16`, `armv8_crc32`) replace `getauxval` in `cpu_has` (`:2221-2245`); `neon` and `fp-armv8` are true on every Apple arm64 chip. The `#elif defined(__aarch64__) && defined(__linux__)` guard gains an `__APPLE__` branch; `zs_cpu_supports` (`:2250`) is unchanged, so `[<Multiversion>]` dispatch works as on Linux.
- **Backtraces:** libSystem has `execinfo.h`, so the `__GLIBC__` guard (`:12`, `:59`) becomes `__GLIBC__ || __APPLE__`. `backtrace_symbols_fd` names the symbols `dladdr` finds, the exported ones, which is what glibc gives with `-rdynamic` today; Z# names for the internal functions come with [0011](0011-debug-info-profiles-traces.md)'s panic backtraces (track D's debugging item 5) on every OS at once.
- **Unchanged:** `pthread` throughout (the pool, channels, the helper thread), `clock_gettime(CLOCK_MONOTONIC)` (macOS 10.12 and later), `posix_spawn`, `getaddrinfo`, `dirent`, `sysconf(_SC_NPROCESSORS_ONLN)`. `accept4` and `SOCK_NONBLOCK` are Linux: `accept` plus `fcntl(O_NONBLOCK | FD_CLOEXEC)` behind the same two lines (`:1603`, `:1618`).

### The runtime on Windows

One `#ifdef _WIN32` section, each POSIX call replaced behind the `zs_*` function that wraps it, so the Z# library sees the same `Native.*` builtins (facts sheet §12 lists the 41):

| Today (POSIX) | On Windows |
|---|---|
| epoll (`:1078`, `:1120`, `:1498`) | **wepoll:** `wepoll.c` and `wepoll.h` (MIT, one file each) give `epoll_create1`, `epoll_ctl` and `epoll_wait` over an IOCP, so the loop's code is the same. wepoll watches sockets only, so the inbox's wake pipe becomes a loopback socket pair (what CPython's `socketpair` and libuv do on Windows), and waits are keyed by a small hash table instead of the array indexed by descriptor (`L.fds`, `:1130`), since a `SOCKET` is a handle value, not a small integer |
| `pipe2`, `read`, `write`, `close` on sockets | `send`, `recv`, `closesocket`; non-blocking by `ioctlsocket(FIONBIO)`; `WSA_FLAG_NO_HANDLE_INHERIT` for `SOCK_CLOEXEC`; errors from `WSAGetLastError` through `FormatMessageW` into `Native.errorText`; `WSAStartup` once at `zs_loop_enter` |
| futex (`:2047-2048`) | `WaitOnAddress` and `WakeByAddressSingle` (`synchronization.lib`, Windows 8 and later): the same wait-while-equal shape |
| `pthread_create`, `pthread_join`, `pthread_mutex_*`, `pthread_cond_*`, `pthread_cond_timedwait` | `_beginthreadex` and `WaitForSingleObject`, `SRWLOCK` (`AcquireSRWLockExclusive`), `CONDITION_VARIABLE` (`SleepConditionVariableSRW`, with a millisecond timeout where the pool waits with `CLOCK_REALTIME`, `:1923-1929`) |
| `fopen`, `fread`, `fwrite`, `stat`, `remove`, `mkdir`, `opendir`, `readdir` | the `W` calls (`_wfopen`, `_wstat64`, `_wremove`, `_wmkdir`, `FindFirstFileW`, `FindNextFileW`) behind one helper that turns a Z# string (UTF-8) into UTF-16 and back; absolute paths longer than 260 characters get the `\\?\` prefix there |
| `getenv` | `GetEnvironmentVariableW`, through the same helper |
| `posix_spawn`, `pipe`, `waitpid` (`:930-962`) | `CreateProcessW` with `CreatePipe` for standard output (inheritable write end, read on the calling thread as today), `WaitForSingleObject`, `GetExitCodeProcess`; `SearchPathW` for the PATH lookup; the argument list becomes one command line quoted by the rules `CommandLineToArgvW` parses, so `Process.run "git" [ "commit"; "-m"; "a b" ]` arrives in three arguments |
| `clock_gettime(CLOCK_MONOTONIC)` (`:172`) | `QueryPerformanceCounter` scaled to nanoseconds by `QueryPerformanceFrequency` |
| `sysconf(_SC_NPROCESSORS_ONLN)` (`:1445`, `:1972`) | `GetSystemInfo().dwNumberOfProcessors` |
| `__builtin_cpu_supports` (`:2197`) | the same: it's a compiler builtin over `cpuid`, and mingw's clang has it |
| `backtrace` | `CaptureStackBackTrace`, with names from DbgHelp's `SymFromAddr` where the PE's symbol table has them and addresses otherwise |
| `_exit(134)` (`:48`) | the same; the exit code is a number on Windows too, and `zs test` compares it |
| `main`'s `argv`, which `zs_test_index` reads (`:952` in the facts sheet) | `GetCommandLineW` and `CommandLineToArgvW`, converted to UTF-8 once at startup, so `Native.arg` is UTF-8 on every OS |

- **The console is UTF-8:** `SetConsoleOutputCP(CP_UTF8)` and `SetConsoleCP(CP_UTF8)` at startup, and `_setmode(_fileno(stdout), _O_BINARY)` for standard output and error, so `println` writes the bytes `Show` produced and `\n` is not turned into `\r\n`. A `.out` test's expected output is then the same file on every OS.
- **The driver links** `-lws2_32 -lsynchronization -ldbghelp` for this target and compiles `wepoll.c` next to `rt.c` (it lives in `runtime/`, with its license). Nothing is a run-time dependency beyond Windows itself.
- **What stays:** the pool, channels, the inbox protocol, the timer heap, Perceus's counts, the allocator's pool and every `Native` function's signature. 0008's spare threads and cancellation through inboxes are OS-independent and work here unchanged.

### `Path` on Windows

[0024](0024-library-api.md) specifies `Path` on POSIX paths; this proposal owns Windows's rules, and the separator is the target's at run time in both:

- **`Path.separator : string`** is `"\\"` on Windows and `"/"` elsewhere (a constant per build, from a `Native` builtin). `Path.combine` joins with it.
- **Both separators are separators** on Windows: `getFileName`, `getDirectoryName`, `getExtension` and `changeExtension` split at the last `\` or `/` (`lib/std/IO/Path.zs:12-25` split at `/` only). Forward slashes in input are kept as written, since Windows accepts them; nothing normalizes.
- **Absolute** on Windows means a drive and a separator (`C:\x`), a UNC path (`\\server\share\x`), or a rooted path (`\x`), and `combine` returns an absolute second argument whole, as on POSIX: `Path.combine "C:\\a" "D:\\b"` is `D:\b`. A bare drive joined with a name is drive-relative, `C:x`, as .NET's `Path.Combine` gives; `getDirectoryName "C:\\a"` is `C:\`.
- **Case:** paths compare as strings, ordinal, everywhere; the file system's case-insensitivity isn't modelled, as .NET doesn't model it. Nothing in `Path` touches the file system (its header says so).
- **Core and Std placement** is the ledger's and 0024's, unchanged by targets: `Path`, `File`, `Directory`, `Process`, `Net` stay in Std; a target with an OS has all of Std.

### The manifest

The per-target table [0014](0014-placement.md) introduces (`[target.<name>]` with `heap` and `stack` for chips) takes a `.c` subtable for C flags that apply to one target only, as [0018](0018-packages.md) defines for a package's C dependencies:

```toml
[target.aarch64-macos.c]
flags = ["-framework", "CoreFoundation"]       # passed to zig cc for this target only

[target.x86_64-windows-gnu.c]
flags = ["-lws2_32"]                           # a project's own sockets code; the runtime adds its own
```

`[<Link "name">]` stays the per-file form (DESIGN §11); the table is for what differs by OS.

### Linking, LTO and signing

- **The first implementation links as the cross builds do today:** clang compiles the IR to an object with `--target=`, `zig cc` compiles `rt.c` and links (`src/Driver.fs:1836-1842`). No ThinLTO, so the runtime's allocation functions aren't inlined, as on `aarch64-linux-musl`.
- **Then ThinLTO through zig's lld:** `zig cc -flto=thin` links with lld for every target (ld64.lld for Mach-O, lld-link for PE), and the modules and `rt.c` go in as bitcode as the host build does (`:1672`, `:1730`). The cache directory is a linker flag per flavor (`-Wl,-cache_path_lto,<dir>` for ld64.lld, `-Wl,/lldltocache:<dir>` for lld-link), under `.zs-cache/lto` as today. A native build on a Mac uses ThinLTO when `ld64.lld` is on PATH, as the Linux build checks for `ld.lld` (`:1628-1632`).
- **Signing:** an arm64 Mach-O executable must be signed or macOS kills it at launch. ld64.lld signs ad hoc by default on arm64, and Apple's ld64 does the same, so both paths produce a binary that runs on the building machine and any other without Gatekeeper's quarantine (a download, not a build). Signing with a Developer ID and notarization for distribution are *Unresolved questions*.
- **Native builds on a Mac** use the installed clang and ld64 as a native Linux build uses clang and ld (`:1877`); `-rdynamic` is accepted by clang on Darwin as `-export_dynamic`. The compiler itself is a .NET publish for macOS arm64 before phase 11 and a Z# binary cross-compiled by this very path after it ([0020](0020-self-hosting.md)).

### `zs doctor` and the release archive

Phase 12's `zs doctor` checks, per target: `clang` recent enough to read the IR `zs` writes (Apple's clang lags LLVM's releases by a year or more and may not parse the debug records in it, so it names Homebrew's or LLVM's own `llvm`), `zig` for a cross build, `ld64.lld` or `lld-link` for ThinLTO, `dsymutil` for a `.dSYM`, and libclang for `import c`. The release archive for `aarch64-macos` holds `zs`, `runtime/` and `lib/`, as the Linux one does.

### Testing

- **macOS:** `./test.sh` runs natively on GitHub's arm64 macOS runners (`macos-14` and later are M-series), with no `--target`: the native path, the ABI by the host triple, kqueue, the LSP and MCP scripts, the C interop directories and the `.so` tests as `.dylib`. The `.host-only` sidecars (4 files) mean "not under qemu", and run.
- **Windows:** `./test.sh --target x86_64-windows-gnu --build-only` builds every `.out` test program and every C interop test (`main.c` with `zig cc -target`, `test.sh:203`) and runs none; `.err` tests run as usual, since the compiler runs on the host; the host-only script block is skipped. A failed build is the test's failure, with the build log.
- **Exit tests** are the roadmap's: `./test.sh` passes on macOS arm64; every test program builds for Windows.
- **Unit tests in `rt.c`'s port** are the existing programs: `tests/task/`, the echo server's soak under `bench/echo/`, `tests/chandle` for handles, run on a Mac in CI and, for Windows, by hand on a machine until one is in CI.

### Order of implementation

1. **The host triple** in the driver and `Codegen`'s classification by it (`isApple`, `isWindows`, a real `isArm64`): the aarch64 Linux fix lands first and is tested under `./test.sh --target aarch64-linux-musl` under qemu, where the native and cross results can be compared.
2. **macOS: `rt.c`'s four blocks** (kqueue, the mutex wait, `sysctl`, backtraces) and the `accept4` line, compiled with `zig cc -target aarch64-macos` from Linux; a hello world and the task tests run on a Mac by hand.
3. **macOS in CI:** the suite on the arm64 runner, then the `.dylib` and interop tests, then ThinLTO through ld64.lld, then `-g` with lldb ([0011](0011-debug-info-profiles-traces.md)'s lldb item is "the same as gdb", and starts here). Phase 12's release archive for macOS closes the item.
4. **Windows: `Codegen`'s `abiWin64` and `cModes`'s one budget,** `import c`'s LLP64 mapping; the test is the C interop directories under `--build-only`, and a struct-passing program checked by hand on a Windows machine.
5. **Windows: `rt.c`** in the order a program meets it: console and panics, files and `Path`, threads and the mutex, the loop over wepoll, sockets, processes.
6. **`--build-only` in `test.sh`,** and the exit test. Running the suite on a Windows runner is after 0.1, when a machine exists for it.

Each step keeps `./test.sh` green on Linux, and the `.same-ir` tests say the IR for Linux didn't move.

## Drawbacks

- **Three OS-specific blocks in one C file.** `rt.c` is 2,258 lines today (main working tree); the Windows block is an estimated 600-900 more and wepoll 2,500 of someone else's. The `zs_*` functions keep the OS code behind one interface, but a change to the loop is now tested on three kernels.
- **wepoll is a dependency,** the first C file in `runtime/` not written for Z#. It's one MIT file with no build system, vendored, and the alternative (IOCP directly) is a loop of a different shape (*Unresolved questions*).
- **Windows is build-only** until a machine runs the tests, so a regression in the Windows runtime is found by hand. Decision 29 accepts this; the exit test is honest about it.
- **Two ABIs more to get right by hand.** `Codegen` classifies structs itself rather than letting clang do it (the IR is textual, decision 51), so each convention is Z#'s own code and its own tests.
- **`long` differs per target** in `import c`, so a `[<CLayout>]` record written against a Linux header can be the wrong size on Windows. [0004](0004-c-layout.md)'s compile-time `assert (sizeof<T> = n)` is the check, per target.
- **Apple's toolchain is a moving target:** `os_sync_wait_on_address` is 14.4, ad-hoc signing rules are the kernel's, and a release archive needs notarization to download cleanly. Each is one block or one step, but each is Apple's to change.

## Alternatives

- **A native Windows toolchain (MSVC, `x86_64-windows-msvc`).** Needs Visual Studio and runs on Windows only, so no cross build from Linux and no `--build-only` test in today's CI; the convention and the UCRT are the same through mingw-w64. Not chosen; `windows-msvc` through Zig (which can link against MSVC's libraries when they're installed) is a target name away if a user needs a PDB.
- **libuv for the loop,** on every OS at once. A runtime dependency of 50,000 lines where the loop is a few hundred lines of C with one interface (`zs_loop_*`), and libuv's callbacks would wrap Z#'s closures a second time. Not chosen.
- **IOCP directly** instead of wepoll: a completion-based loop (overlapped reads with buffers handed to the kernel) where Z#'s is readiness-based; the library's `Native.fdRead` and `tcpAccept` would change shape for one OS. Not chosen for the port; whether it comes later is unresolved.
- **WSL only:** a Linux binary under Windows, which `aarch64-linux-musl`'s path gives already for x86-64. Not a Windows target: no `.exe`, no Win32, nothing a Windows user ships.
- **Cygwin or MSYS2's POSIX layer:** a 3 MB DLL every binary depends on, and a POSIX emulation of the loop over a Win32 emulation. Not chosen.
- **`mach_absolute_time`, `GCD`, `dispatch_semaphore` for the Mac's primitives:** Apple-specific where `clock_gettime`, `pthread` and `os_sync_*` are enough, and the pool is Z#'s own (0008). Not chosen.
- **Keeping `Path` POSIX-only** and letting Windows users write `/`: Windows accepts `/` in most APIs, but prints `\` from `Directory.list` and `Environment`, so the split functions must know both; `separator` costs one builtin. Not chosen.
- **Doing nothing until after 0.1 for macOS as well as Windows.** Phase 12's exit test names macOS, and the people it's for are there. Not chosen.

## Compatibility

- **Not a breaking change.** No syntax, no type, and no Core function changes; `--target` accepts two more names; `Path` gains `separator` and its split functions accept `\` on Windows only.
- **An older compiler** given `--target aarch64-macos` passes the name to clang and `zig cc` as it passes any triple; the build stops when `zig cc` compiles `rt.c`: `sys/epoll.h: file not found`. Given `x86_64-windows-gnu`, the same at `unistd.h`'s functions. Neither produces a binary, so nothing half-works.
- **Compiled binaries:** none to consider; packages are source (decision 27). A package's `[target.<name>.c]` table is read by compilers that know it and is an unknown section (an error, facts sheet §9) in older ones, as 0018 says.
- **The library:** Std's surface is the same on every OS; every `Native.*` builtin keeps its name and type. A program that reads `Path.getDirectoryName` of a path with backslashes gets a different answer on Windows than on Linux, which is the point.
- **`import c`** on Windows sees `long` as `i32`: a binding written for Linux and built for Windows may change a record's layout, and 0004's `assert` catches it at compile time.
- **Microcontrollers:** untouched. `rt-embedded.c` has no OS and the chip targets keep their triples; the thumb AAPCS struct gap (`src/Codegen.fs:442-443`'s ponytail note) is out of scope here and stays a known gap.
- **Cross builds from macOS and Windows hosts** to Linux and to chips go through `zig cc` as from Linux, once the compiler runs there.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| a target name the driver doesn't know | `unknown target 'aarch64-darwin': zs builds for aarch64-linux-musl, aarch64-macos, x86_64-windows-gnu, cortex-m4 and cortex-m0plus` |
| a cross build without Zig | `zig is not on PATH: a build for aarch64-macos needs it (zs doctor says where to get it)` |
| `-o app.so` for a Windows or macOS target | `'.so' is a Linux shared library; for x86_64-windows-gnu write 'app.dll'` (`app.dylib` for macOS) |
| `--sanitize` on a cross build for Windows | `--sanitize isn't available for x86_64-windows-gnu (the sanitizers' runtime is the host's); run the sanitized tests on Linux` |
| `zig cc` fails on the runtime (an SDK stub missing, an old Zig) | `zig cc failed:` and its output, as today (`src/Driver.fs:1842`) |
| a `[target.<name>.c]` table for a target the compiler doesn't know | `zs.toml: unknown target 'x86_64-windows' in [target.x86_64-windows.c]; did you mean x86_64-windows-gnu?` |
| `Path.combine` with a drive-relative first argument (`"C:"`) | none: `C:x` is the answer, as .NET's; the reference page says so |
| run time, Windows: a wait on a handle wepoll can't watch (a file, a pipe) | `panic: epoll_ctl failed (a descriptor that isn't a socket?)`, today's message (`rt.c:1120`) with the OS's word |

### Tooling

- **`zs lsp`** checks for the host, since the checker has no target: hover on a field `import c` made from a C `long` shows `int` in the editor on Linux and the build for Windows uses `i32`. Completion, definition, references, inlay hints and diagnostics while editing are the checker's and the same on a Mac as on Linux, with no build run; the server itself runs on macOS and Windows as a .NET publish, then as a Z# binary. A `[lsp] target =` setting is an *Unresolved question*.
- **The tree-sitter grammar** gains nothing: there is no syntax here. The Zed extension runs on macOS and Windows as it does on Linux, since it's WASM.
- **lldb:** `zs build -g` writes DWARF into the object as today; on macOS the executable carries a debug map pointing at the object, which the driver keeps in `.zs-cache/objects` for a `-g` build instead of deleting it (`src/Driver.fs:1844-1845`), so lldb finds the lines and locals without `dsymutil`; `dsymutil` makes a `.dSYM` for distribution when it's on PATH. On Windows the DWARF stays in the PE, which lldb and gdb read (no PDB). 0011's pretty-printers and DAP launch configurations cover lldb from the same DWARF.
- **`zs doctor`** names what each target needs (above). **`zs test`** on a Mac runs each test in its own process as on Linux; `ZS_BACKTRACE=0` keeps the output deterministic there too.
- **Profiling:** `ZS_STATS=1` prints the runtime's counters on every OS (0011 owns them); `zs profile` runs samply on macOS (its home platform) and perf on Linux; Windows waits.

### Performance

- **Existing code:** nothing changes for Linux. Z#-to-Z# calls use LLVM's internal convention everywhere, so the C ABI work costs C calls only, and only what the convention demands.
- **kqueue** registers and waits in one `kevent` call, so a loop that arms a descriptor and waits makes one syscall where epoll makes two; the echo server's 10,000 connections (DESIGN §6) are within kqueue's design range.
- **wepoll** polls sockets through AFD and costs one device call per arm, which is more than epoll per readiness; a loop at its shape is correct first. IOCP directly would be faster for a server with thousands of sockets, and is unresolved.
- **`Mutex`:** `os_sync_wait_on_address` and `WaitOnAddress` are kernel waits as the futex is; the uncontended path (one compare-and-swap, `rt.c:2056`) is the same on every OS.
- **`Runtime.ticks`:** `QueryPerformanceCounter` resolves to about 100 ns, where `CLOCK_MONOTONIC` resolves to nanoseconds; `Stopwatch` says so on its reference page.
- **Without ThinLTO** (the first macOS builds), allocation-heavy programs run as the `aarch64-linux-musl` cross builds do: `binarytrees` is 0.43 s against 0.31 s with ThinLTO on Linux ([the host report](../reports/host.md)); ThinLTO through ld64.lld is step 3.
- **The compiler's time** is unchanged: a cross build is clang once and `zig cc` once, as today; the Windows link adds `wepoll.c`, compiled once into the object cache.

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| targets the driver knows | 5 names (two chips, three OS triples) and the host | 20: a name per row in the table, nothing per-target in `Codegen` beyond the ABI classification |
| sockets in one loop (kqueue, wepoll) | 100 | 10,000 (the echo server's soak), one wait record each |
| path length on Windows | 100 characters | 32,767 with the `\\?\` prefix the conversion helper adds past 260 |
| `Process.run` arguments on Windows | 5 | 32,767 characters of command line, the OS's limit, which `Native.runProcess` reports as an error rather than truncating |
| OS-specific lines in `rt.c` | 0 today | estimates: 150 for macOS, 600-900 for Windows, plus wepoll's 2,500 vendored |
| CI time for the suite on the macOS runner | estimate: the Linux suite's time plus the runner's slower disk, under the 20 minutes GitHub's free arm64 runners allow per job | one job per push |

### Culture-aware formatting and parsing

- **None in the language or the runtime:** `Show` and the parsers are invariant on every OS (0024), and the console is UTF-8 on Windows, so a program prints the same bytes everywhere.
- **File names** cross the UTF-8 and UTF-16 boundary on Windows losslessly for every well-formed name; an NTFS name with an unpaired surrogate (legal on NTFS, not encodable in UTF-8) comes in as U+FFFD and can't be named from Z#. Rust carries an `OsString` for this case; Z# takes the loss, as .NET does when it writes such a name to a UTF-8 file.
- **Paths** aren't culture: the separator and the drive are the OS's, not the user's locale's.

## Unresolved questions

1. **IOCP directly, long-term.** This proposal keeps the readiness loop over wepoll (one file, the loop's shape kept); a completion-based loop would change `Native.fdRead`'s and `tcpAccept`'s shape for one OS. Decide after a Windows machine runs the suite and a server benchmark exists there.
2. **`long`'s width in `import c`:** `i32` on Windows by the target's data model (this proposal), or a `c_long` type in the prelude that is `int` or `i32` by target, so a binding reads the same on both. The second adds a type for one case; the first makes a Linux binding silently 4 bytes narrower on Windows, caught by 0004's `assert`.
3. **Code signing for distribution:** ad-hoc signing (this proposal: what the linkers do) runs a binary a user built; a downloaded one needs a Developer ID signature and notarization, which cost an Apple account and a `codesign` step the release pipeline would run, or the user's `xattr -d com.apple.quarantine`. Phase 12's release decides, since it's the release's problem, not the compiler's.
4. **The Windows loop's descriptor model for `Net.Tcp`:** sockets are `SOCKET` handles and files are `HANDLE`s, both in a `zs_int`, keyed by a hash table (this proposal); a small table of the program's own indices (as `L.fds` is today) would keep the array but needs a free list. Settle while writing the port.
5. **A target for the editor:** `zs lsp` checks for the host (this proposal); an `[lsp] target = "x86_64-windows-gnu"` line in `zs.toml` would make hover show `i32` for `long` and the Std-missing errors for a chip project. Cheap once the checker takes a data model; not before.
6. **Threads on Windows through winpthreads** (mingw-w64 ships it) instead of `_beginthreadex` and SRW locks (this proposal): it would leave the thread code untouched at the cost of a library the binary links statically. Measure the binary's size when the port starts and take the smaller.
7. **A new decision row,** numbered by the coordinator, recording the two target names, mingw-w64 over MSVC, wepoll over IOCP, and the `Path` rules above; decision 29 stays the order.

## History

- **2026-10-24:** implemented (decision 82). Settled while porting: threads through winpthreads (question 6: zig ships it, and the thread code stays as it is); sockets as indices into the runtime's own table (question 4); `__ulock_wait` on every macOS, not `os_sync_wait_on_address` (one call for every version); file names, arguments and the environment through the narrow (`A`) calls, in UTF-8 because every program embeds a manifest whose `activeCodePage` is UTF-8 (`runtime/utf8.rc`) and sets the C runtime's locale to `.UTF8`: Windows 10 1903 and later, where the proposal's UTF-16 helper would have needed a wide call at every site; `long` 32 bits on Windows by the target's data model (question 2's first answer). Windows on arm64 and Linux arm64 build by the same code, and Wine runs Windows's suite in the dev container.
- **2026-10-22:** drafted from track T's plan, phase 12's "macOS arm64" item, DESIGN §6, §10 and §11, and the facts sheet's survey of `rt.c`'s POSIX surface and `Codegen`'s ABI code.
