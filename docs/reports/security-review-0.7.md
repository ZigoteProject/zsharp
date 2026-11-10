# Security and stability review of 0.7.0

A review of the whole of 0.7.0 (`5d1628c`, and `fb9d178` after it) for defects an attacker can
reach and for crashes, hangs, leaks and races a program can hit: the compiler, the C runtimes, the
library, the language and build servers, the package manager, the scripts and CI, and the editor
extensions. It found 105 distinct defects (121 reports, some the same defect seen from two
places, two of them found by CI on the fixes' own tests): 1 critical, 30 high, 47 medium and 27
low. 102 are fixed on
`claude/security-stability-review-lgcqg3`, each with a test; two are fixed in part and one is
deferred, each with the design that finishes it (below).

## How it was done

- **Found:** fourteen reviewers, each over one part of the tree (the three parts of `rt.c`, the
  embedded runtime and host, two of `lib/core`, `lib/std`, the services, the package manager, the
  front end, the checker's safety rules, the optimizer and code generator, and the scripts, CI and
  editors), each reading its files whole and following calls out of them. The trust model they
  worked to: compiling one's own code is not a boundary; a project opened in an editor, the MCP
  server, the build server's socket, a fetched package and the input a Z# program reads are.
- **Verified:** every report went to a reviewer told to refute it, reading the code and its
  callers, and reproducing C defects under AddressSanitizer, UndefinedBehaviorSanitizer or
  ThreadSanitizer (most of the runtime's were). One report was refuted; the 19 that the review's
  own budget left unverified (the package manager's 14, five of the first round's) were confirmed
  by the reviewer who fixed them, before fixing.
- **Fixed:** in twelve parts, each in a worktree of its own, then reviewed by another reviewer told
  to find what breaks (the build, a caller, a test's expected output, the bootstrap) and revised.
  The reviews found real faults in five of the twelve: a crash at a library's unload from two
  fixes together, a cache path made of a dependency's own name, guards that performed an effect,
  a decimal literal one past `i64`, and a chip stack the layout change had shrunk.
- **Tested:** the review's machine could not run `zs` (a downloaded compiler isn't run there), so
  the C was compiled (clang, gcc, both chips' targets) and tested under the sanitizers there, and
  every Z# change was tested by CI's Linux x86-64 job: the whole suite in the dev container, the
  chips' programs under QEMU, wasm32's under Node, and `tests/bootstrap.sh`, the compiler built by
  itself to the same bytes. CI's runs on the merged fixes failed mostly on the tests' own
  mistakes (an array shown, `JNumber -1.25e-5` read as a subtraction, `3e-7` as three tokens, a
  mode read after a `chmod`, `Runtime.mallocs` counting every task's frame, `zs fmt`'s spacing of
  a minus after `>`, a test port drawn from the range the system gives clients), once on two
  fixes that met only when merged (a library-only rule and four new uses in the compiler), and
  twice on defects older than the review that its tests were the first to reach: R3-1, a
  literal only a library trait constrains defaulting to `i16` (`Binary.toBytes 70000` wrote
  4464), and R3-2, a tail call the Cortex-M0 and WebAssembly can't make. Each is fixed in its
  own commit. At `32ff96a` every job that passed at `fb9d178` passes: Linux x86-64's (the suite,
  the bootstrap, the chips under QEMU, wasm32 under Node, the six release archives), and the
  suites of Linux arm64, macOS arm64 and macOS Intel, each with its own archive.

## What changes for programs and users

- **The editor and the MCP server don't run a project's code** unless told to: `zs lsp --trust`
  and `zs mcp --trust` build and run a dependency's type provider; without it, the module from
  the last trusted build is used (with a warning), else the import is an error that says why.
  VS Code's extension, which runs only in trusted workspaces, passes `--trust`; Rider's passes it
  for a trusted project; Zed's doesn't (its README says how). `zs build`, `zs check` and the
  other commands run providers as before, as `cargo check` runs build scripts.
- **A Buffer read in a loop is checked:** loop versioning took a Buffer's owner pointer for its
  length, so `b.[i]` past the end read the heap in a `for` loop; Buffers keep their per-access
  check, which a loop over one pays for (`Sha256`'s message schedule, say).
- **`Spsc` takes any number of producers and consumers:** it was Share, so safe code could pop
  one queue on two threads and free a value twice; it's now Vyukov's bounded queue in both
  runtimes, and still never waits (a handler pushes and pops as before).
- **On a chip, a stack overflow is a panic,** `panic: stack overflow (recursion too deep)`, not
  memory overwritten: the stack is at the bottom of RAM, below `.data`, `.bss`, `.noinit` and the
  heap, with an MPU guard below it where the core has one. The heap masks interrupts while it
  changes.
- **`Json`:** a new case, `JUInt`, for integers from 2^63 to 2^64 - 1 (a `match` on `Json`
  without a wildcard needs it); `Json.parse` nests at most 32 levels where `int` is 32 bits
  (1,000 elsewhere). **`Binary.ofBytes`** stops at the same depths with an Error
  (`Binary.ofBytesWith { depth }` for another), and refuses a length past the bytes it has.
  **`Hmac.verify`** and **`Bytes.fixedTimeEquals`** compare a tag in constant time.
- **Processes:** a `.bat` or `.cmd` is run through `cmd.exe` with its quoting (as Rust's fix for
  CVE-2024-24576), and an argument it can't carry (a line break) is an Error; `SIGPIPE` is
  ignored, so a write to a closed pipe is an Error (standard output closed still ends the program
  quietly, as `prog | head` expects); a second `Process.wait` gives the same code, and `kill`
  after it does nothing.
- **Files:** `File.copy` of a file onto itself is an Error, and a copy keeps the source's mode; a
  `File.move` across file systems renames a finished copy over the target;
  `Directory.deleteRecursive` removes a symbolic link (or junction) and never what it leads to.
- **Networking:** `Tcp.connect` and `Udp.send` look a name up off the event loop and try each
  address; a port past 65535 is an Error; `Unix.listen` replaces only a socket nothing listens
  on; `Tcp.accept` waits 100 ms before it gives an accept failure (out of descriptors), so the
  guide's loop doesn't spin.
- **Packages:** a symbolic link in a dependency is hashed as a link and never followed, and
  `zs vendor` copies one only when it stays inside its package; a lock entry's name is checked as
  a manifest's; a manifest's `main` is a path inside its package (the project's own too); a
  `zs.toml` is at most 1 MB; what zs keeps for a dependency is in the project's
  `.zs-cache/pkgs/`, never in the dependency's directory or through a link.
- **The thread pool** no longer panics when every spare thread is taken: a job waiting on a lock
  or a channel that a thread outside the pool holds waits (jobs that wait only for each other,
  more than there are threads, hang where they panicked).
- **`Format.format`** with a specifier made at run time takes a letter and at most two digits, as
  a written one does, and panics on another.

## Fixed in part, deferred

- **R2-pkg-14, the lock's hash:** XXH3-128, where proposal 0018 says SHA-256. `src/` builds with
  stage 0's library, 0.6.1's, which has no `Sha256`. Once stage 0 is 0.7.0 or later (or with a
  SHA-256 in `src/host.c` behind an extern, as `readlink` is now): hash with SHA-256 under an
  algorithm prefix, verify an entry without a prefix as XXH3 as now, and rewrite it at the next
  lock write.
- **R2-leftover-9, `[<NoAlloc>]`'s check:** the frees of consumed arguments inside a few
  operations the code generator expands (`print`/`println`, `Spsc.push` on a full queue, a
  consumed `ref` or `Buffer` argument) are still unseen; the drops in primitives the finding named
  are seen. The rest: a table of the arguments each operation drops, which `NoAlloc` turns into
  frees, and `print` lending its argument.
- **R2-leftover-15, CI's downloads:** LLVM (Linux arm64) and micromamba (macOS Intel) are checked
  against their SHA-256s; zig's archives (0.16.0 on Linux arm64, 0.17.0 on Windows) and
  Windows's LLVM 23.1.4 release archive, which master's Windows jobs download since the merge of
  `e6b96a9`, are pinned by version only (their sites couldn't be reached from the review's
  machine to hash them), and Homebrew's formulae and Chocolatey's `pkgconfiglite` are their
  current ones (each checks its installer's checksum itself).
- **Left as they are, and why:** `Tcp.listen` and `Udp.bind` still look a name up on the loop
  (a server's own address, once, at start); a lookup is a thread, without a cap on how many at
  once; an `Spsc` is 232 bytes on a computer (the head and tail on cache lines of their own), past
  the pool's 256-byte objects with its header, so each is a `malloc` (`Task.spawn` and
  `Task.blocking` make one); the deque's resize race is proven by C harnesses, which the suite
  doesn't run (no Z# program reaches the window reliably).

## What wasn't covered

- **Windows at run time:** its code paths were read and, where headers allowed, compiled, but
  CI's Windows jobs fail at `fb9d178` already, before this work, and still do at `32ff96a`: x64's
  suite fails most checks on their output's line ends (126 at `32ff96a`, 143 at `fb9d178`; this
  work's new tests among them, and `zs doctor`, which printed nothing), and arm64's stopped at
  installing its tools, a pin of this work's undone in `8c34c59`. So the Windows parts of the
  fixes (the `.bat` quoting, the socket table, UDP, file IDs, reparse points) are unrun.
- **Vendored code** (`runtime/wepoll`, `packages/xxhash`, the tree-sitter runtime): its version
  and known advisories only.
- **Performance:** the fixes keep the common paths as they were where they could (the review
  measured the Spsc and the deque in harnesses), and `bench/host` gates instruction counts in CI;
  no other benchmark was run.

## The findings

R1 refs are the first round's, R2 the second's (the package manager's, and the first round's
reports whose verification ran then), R3 what CI found on the fixes' tests. A ref after a comma
is the same defect, reported twice.

### Optimizer and code generator

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-0, R2-leftover-2 | critical | Loop versioning reads the wrong length for a Buffer, so b.[i] in a for loop is never bounds-checked (`src/Gen/Fun.zs`) | fixed |
| R2-leftover-1 | high | Moving a mutable into a call, then a `let mutable`, then reassigning it: the reassignment drops the moved value again (UAF / double free) (`src/Opt/Rc.zs`) | fixed |
| R2-leftover-5 | high | `for i in a .. b` never ends when b is near the type's maximum; in the unchecked versioned copy the wrapped variable then indexes out of bounds (`src/Gen/Fun.zs`) | fixed |
| R1-15, R2-leftover-3 | high | Buffer.blit's range check wraps on i + n, so huge offsets write or read before the storage (`src/Gen/Helpers.zs`) | fixed |
| R3-2 | medium | A tail call to another function was a musttail call on a Cortex-M0 and on WebAssembly, which can't make one: LLVM's backend crashed (thumbv6m) or … (`src/Gen/Fun.zs`) | fixed |
| R2-leftover-4 | medium | Simplify keeps what an `if x`/`match x` proved about a `let mutable` x after x is reassigned: later tests of x are decided at compile time (`src/Opt/Simplify.zs`) | fixed |
| R1-46 | medium | A Buffer that grows while owning its storage alone leaks the values left past its length (`src/Gen/Helpers.zs`) | fixed |

### Type checker

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R2-leftover-6 | high | Share check trusts any function-typed expression: a closure returned by a call carries a ref or Buffer onto other threads (`src/Infer/Exprs.zs`) | fixed |
| R2-leftover-8 | high | A nested (non-regular) generic type makes the cycle warning, and shareBlocker, expand without end: checker hang or OOM, so the LSP dies on an … (`src/Infer/Decls.zs`) | fixed |
| R2-leftover-9 | high | [&lt;NoAlloc&gt;] and interrupt-handler check misses heap work done inside primitives (ignore, ref.set and truncate drops; vec.store copy; Buffer … (`src/Opt/NoAlloc.zs`) | partly fixed |
| R3-1 | medium | An integer or float literal that only a library trait constrains (Binary, ToJson, ...) defaulted to the first type with an impl, i16 or f32, not int … (`src/Types/Norm.zs`) | fixed |
| R2-leftover-10 | medium | Checked-module cache key omits the module whose extern a module calls by its bare C name, so a stale check skips type and callback/share checks (`src/Build/Check.zs`) | fixed |
| R2-leftover-7 | low | Internal Native.* builtins are callable from safe code: parJoin forges any type or double-frees a job, loopFulfill turns an int into a pointer write (`src/Infer/Builtins.zs`) | fixed |
| R2-leftover-11 | low | Impl requirements are empty while the impl's own methods are checked, so a use inside the impl at a non-Share type escapes a Share requirement … (`src/Infer/Decls.zs`) | fixed |

### C runtime: memory, formatting, weak references

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-1, R1-5 | high | Format.format trusts the specifier's digits: stack buffer overflow ('B') and stack over-read into the result (D/X/F) with a runtime spec (`runtime/rt.c`) | fixed |
| R1-2 | high | Weak.get on an object moved to another thread (decision 75) takes a non-atomic reference to that thread's object: use-after-free (`runtime/rt.c`) | fixed |
| R1-3 | high | zs_weak_new hands another thread's weak cell, with a thread-local count, to every thread that weakly references a shared object (`runtime/rt.c`) | fixed |
| R1-4 | high | A --lib without handles is built without ZS_THREADS, but its pool, arena and weak tables are then unsynchronised globals a multi-threaded C host … (`runtime/rt.c`) | fixed |
| R1-27 | medium | A thread's pool chunk and free lists are lost when the thread exits (at least 64 KB per thread that allocates) (`runtime/rt.c`) | fixed |
| R1-66 | low | zs_fixed_fail copies the type's name unbounded into char msg[160] (`runtime/rt.c`) | fixed |

### C runtime: files and processes

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-6, R1-21 | high | Windows Process.start/run of a .bat/.cmd passes arguments to cmd.exe unescaped, allowing command injection (BatBadBut) (`runtime/rt.c`) | fixed |
| R1-29 | medium | File.readAllText reads FIFOs and devices with no limit; `import json "/dev/stdin"` in an untrusted file hangs the LSP, and "/dev/zero" exhausts its … (`runtime/rt.c`) | fixed |
| R1-30 | medium | Process.run reports exit code 0 for a failed program when waitpid fails (SIGCHLD inherited as ignored, or EINTR) (`runtime/rt.c`) | fixed |
| R1-31, R1-52 | medium | File.copy and cross-filesystem File.move create the target with mode 0666&~umask, turning a 0600 secret into 0644 and dropping exec bits (`runtime/rt.c`) | fixed |
| R1-32, R1-53 | medium | File.copy onto the same file truncates it to 0 bytes and reports success (`runtime/rt.c`) | fixed |
| R1-33 | medium | Process.run's pipe is not close-on-exec, so processes spawned concurrently inherit it and Process.run hangs until they exit (`runtime/rt.c`) | fixed |
| R1-67 | low | Process.start with a relative program and a directory checks one file and runs another (posix_spawn resolves the path after chdir) (`runtime/rt.c`) | fixed |
| R1-68 | low | Unchecked malloc/realloc in file, directory and process reads: on allocation failure the runtime writes through NULL+offset instead of panicking (`runtime/rt.c`) | fixed |

### C runtime: event loop, sockets, threads

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-7, R1-20 | high | Chase-Lev deque: a thief can pair the new buffer with the old capacity (or the reverse) during a resize, so jobs are lost (join hangs forever) or a … (`runtime/rt.c`) | fixed |
| R1-8 | high | Spsc is Share but not safe for more than one producer or consumer: safe Z# code that pops one Spsc from two threads double-frees (`runtime/rt.c`) | fixed |
| R1-9 | high | Windows socket table: sk_of()/is_sock() read socks[] and nsocks without socks_mu while sk_add() reallocs the array on another thread (use-after-free) (`runtime/rt.c`) | fixed |
| R1-10 | high | accept() failing with EMFILE/ENFILE returns at once, and the documented accept loop then livelocks the server for good: no fd event is ever polled … (`runtime/rt.c`) | fixed |
| R1-34 | medium | zs_loop_step never polls the kernel while the ready queue is non-empty, so a task that keeps yielding starves all I/O, inbox results and … (`runtime/rt.c`) | fixed |
| R1-35 | medium | Timer arithmetic: a sleep longer than about 24.8 days never fires on an idle loop (int truncation to a negative, i.e. infinite, timeout), and … (`runtime/rt.c`) | fixed |
| R1-36 | medium | At exit, pool_stop frees P.freed before loops_stop joins the loop threads, whose TLS destructor slot_give then writes into the freed array (`runtime/rt.c`) | fixed |
| R1-37 | medium | The thread pool panics ("spare threads are exhausted") when jobs wait on a Mutex or Channel that a non-pool thread will release or feed, so a correct … (`runtime/rt.c`) | fixed |
| R1-38, R1-56 | medium | Tcp.connect and Unix.connect leak the connecting socket when cancelled (Task.timeout or race) while waiting for the connection (`lib/std/Net/Tcp.zs`) | fixed |
| R1-39 | medium | Tcp.connect, Udp.send and Tcp.listen call blocking getaddrinfo on the event-loop thread, so one slow DNS lookup stalls every task on that loop (`runtime/rt.c`) | fixed |
| R1-70, R1-82 | low | Unix.listen unlinks whatever file is at the path, not only a stale socket: a regular file is deleted, and a live server's socket is silently taken … (`runtime/rt.c`) | fixed |
| R1-71 | low | Ports are not range-checked: glibc's getaddrinfo reduces a numeric service modulo 65536, so a port that passed a program's filter reaches a different … (`runtime/rt.c`) | fixed |
| R1-72 | low | Windows UDP: Udp.receive returns an Error for oversized datagrams (WSAEMSGSIZE) and after any ICMP port-unreachable (WSAECONNRESET), both of which a … (`runtime/rt.c`) | fixed |

### Microcontrollers, the compiler host, libclang

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-11 | high | No stack-overflow protection on chips: recursion silently overwrites .noinit, .bss and the heap (Json.parse's default depth is enough to trigger it) (`runtime/boards/cortex-m.ld`) | fixed |
| R1-12 | high | The embedded heap is not re-entrant, but Z# code that allocates can run in interrupt context through callback&lt;share&lt;F&gt;&gt; and C-called … (`runtime/rt-embedded.c`) | fixed |
| R1-13 | high | C malloc/calloc/realloc over the Z# heap return undersized or overlapping blocks for sizes near SIZE_MAX instead of failing (`runtime/rt-embedded.c`) | fixed |
| R1-14 | high | Format.format with a runtime spec overflows a stack buffer in zs_format_int (non-digit characters become huge widths) (`runtime/rt-embedded.c`) | fixed |
| R1-41 | medium | host.c's stack raise backfires: with `ulimit -s unlimited` the compiler's pool threads get 8 MB instead of 256 MB, and with a finite limit every … (`src/host.c`) | fixed |
| R1-73 | low | libclang is loaded by bare name, which searches the current directory on Windows and macOS: an untrusted project can plant libclang.dll/.dylib and … (`packages/libclang/c/shim.c`) | fixed |
| R1-74 | low | zs_fixed_fail copies the type name into a 160-byte stack buffer with no bound (`runtime/rt-embedded.c`) | fixed |
| R1-75, R1-79 | low | Float.parse on chips wraps the exponent in an int: "1e4294967306" parses as 1e10 and "1e2147483648" as 1 (`runtime/rt-embedded.c`) | fixed |
| R1-76 | low | Libclang.parse encodes arguments as NUL-separated text, so an argument containing a NUL becomes several clang arguments and pushes out the real ones (`packages/libclang/src/Libclang.zs`) | fixed |

### Core library: bytes and collections

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-16 | high | Binary.ofBytes panics on a crafted string length instead of returning Error (`lib/core/Binary.zs`) | fixed |
| R1-42 | medium | Binary reading has no nesting limit: deep input for a recursive type overflows the stack (`lib/core/Binary.zs`) | fixed |
| R1-43 | medium | Binary corrupts int and i64 values on 32-bit targets (wasm32, Cortex-M) (`lib/core/Binary.zs`) | fixed |
| R1-44 | medium | Bytes.remaining always panics with integer overflow for a growing Writer (`lib/core/Bytes.zs`) | fixed |
| R1-45 | medium | Show for lists is quadratic: printing a long list effectively hangs (`lib/prelude.zs`) | fixed |
| R1-77 | low | Irq.enable, disable and pend don't bound the line number and can write other System Control Space registers (`lib/core/Irq.zs`) | fixed |
| R1-78 | low | Iter's Range panics after the last element when the range ends near Int.max or Int.min, and hangs on step 0 (`lib/core/Iter.zs`) | fixed |

### Core library: text, JSON, time, crypto

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-17 | high | Json.parse decodes escaped strings in quadratic time: the language server hangs on large or hostile files (`lib/core/Text/Json.zs`) | fixed |
| R1-18 | high | Json.parse's default depth of 1000 overflows the 4-32 KB stack on Cortex-M, corrupting memory silently (`lib/core/Text/Json.zs`) | fixed |
| R1-47 | medium | DateTime.parseIso / ofParts panic with integer overflow on valid 2262 dates instead of returning None (`lib/core/Time/DateTime.zs`) | fixed |
| R1-48 | medium | Task callback ids are a 32-bit int on chips and wasm32: a task that waits in a loop panics after 2^31 waits (`lib/core/Threading/Task.zs`) | fixed |
| R1-49 | medium | JSON integers in [2^63, 2^64) silently change value through Json.parse / FromJson&lt;u64&gt; / ToJson&lt;u64&gt; (`lib/core/Text/Json.zs`) | fixed |
| R1-50 | medium | A Signal built in safe code with any id writes outside signal_waiter[32] in the embedded runtime (`lib/core/Threading/Signal.zs`) | fixed |
| R1-51 | medium | String.repeat (and padLeft/padRight) take quadratic time (`lib/core/Text/String.zs`) | fixed |
| R1-80 | low | No constant-time way to check an HMAC tag, although Hmac is offered for JWT verification (`lib/core/Hmac.zs`) | fixed |
| R1-81 | low | Json.print on chips and wasm emits `inf` (invalid JSON) for any number above 1e15 and 0 for small ones (`lib/core/Text/Json.zs`) | fixed |

### Std library: IO, processes, networking

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-19, R1-28 | high | Directory.deleteRecursive follows a symlink or junction given as its path and deletes the target's contents; it also races with symlink swaps (`lib/std/IO/Directory.zs`) | fixed |
| R1-22, R1-40 | high | SIGPIPE is never ignored: writing to a pipe whose reader exited kills the whole program instead of returning Error (`runtime/rt.c`) | fixed |
| R1-54 | medium | Reader.readLine/readToEnd decode each read separately, so a UTF-8 character split across a read becomes 2-4 U+FFFD (`lib/std/IO/Stream.zs`) | fixed |
| R1-55 | medium | Process.wait ties up the loop's only Task.blocking thread until the child exits, so timeouts around it can't work and other blocking tasks stall (`lib/std/Diagnostics/Process.zs`) | fixed |
| R1-58 | medium | Tcp.connect / Udp.send resolve names with blocking getaddrinfo on the event-loop thread, and Tcp.connect tries only the first address (`runtime/rt.c`) | fixed |
| R1-59, R1-69 | medium | Process.kill or a second Process.wait after Process.wait acts on a stale handle (Windows) or a reaped pid (`runtime/rt.c`) | fixed |
| R1-83 | low | Path.getFullPath on Windows drops the UNC root, lets `..` climb above the share, and turns drive-relative paths into path components (`lib/std/IO/Path.zs`) | fixed |

### Build server, LSP, MCP, type providers

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-23, R2-leftover-12, R2-pkg-3 | high | Opening an untrusted project in the LSP (or using MCP check/type_at/explain/build/emit_llvm, or zs check) builds and runs the project's own provider … (`src/Provide/Command.zs`) | fixed |
| R1-24 | high | Type providers write data from the sample file into generated Z# source without escaping, so a JSON key, SVD name or SQL column injects code into the … (`src/Provide/Names.zs`) | fixed |
| R1-60 | medium | Build server deadlocks itself when a served build has to (re)build a packaged type provider, hanging that build and every later one (`src/Server.zs`) | fixed |
| R1-61, R1-57 | medium | runProvider reads the provider's stdout to the end before its stderr, with no timeout: a chatty or stuck provider freezes the LSP, builds and the … (`src/Provide/Command.zs`) | fixed |
| R1-62 | medium | Build server has no timeouts and serializes all requests: one stalled request or client wedges every later build, and neither `zs server stop` nor a … (`src/Server.zs`) | fixed |
| R1-63 | medium | The CSV reader the csv provider writes into programs is quadratic on doubled quotes, a CPU DoS for Z# programs parsing external CSV (`src/Provide/CsvProvider.zs`) | fixed |
| R1-84 | low | Racing server starts leave an orphan that later deletes the live server's socket, cascading (`src/Server.zs`) | fixed |
| R1-85 | low | LSP URI ↔ path conversion ignores the authority and Windows drive letters (LSP unusable on the shipped Windows build; MCP rejects every file there) (`src/Lsp/Rpc.zs`) | fixed |

### Package manager and build caches

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R2-pkg-1 | high | A fetched dependency's symlinked .zs-cache/cimport makes import c's cache overwrite files outside the checkout (e.g. the project's .git/config) (`src/Build/CImport.zs`) | fixed |
| R2-pkg-2 | high | Symlinks inside a fetched dependency are followed by dirHash and zs vendor: local secrets are copied into the committed vendor/ with the hash check … (`src/Build/Project.zs`) | fixed |
| R2-pkg-4 | medium | fetchDeps panics (String.sub out of range) on every run once a default-branch git dependency is in zs.lock (`src/Build/Project.zs`) | fixed |
| R2-pkg-5 | medium | The C sources' object cache keys on the .c file and the .h files in its own directory only: a header changed elsewhere leaves a stale object, so the … (`src/Build/Units.zs`) | fixed |
| R2-pkg-6 | medium | zs writes into dependency checkouts and vendor copies (import c and provider caches, a nested provider build's .zs-cache/deps and zs.lock), which … (`src/Build/Project.zs`) | fixed |
| R2-pkg-7 | medium | A packaged provider is built against its own unpinned dependencies: its git dependencies are resolved outside the user's zs.lock and its hashes, yet … (`src/Build/Modules.zs`) | fixed |
| R2-pkg-8 | medium | Every version entry in zs.lock is checked out and locked again even when no manifest asks for it: zs remove leaves it, and switching a dependency … (`src/Build/Project.zs`) | fixed |
| R2-pkg-9 | medium | zs.lock entry names are used as paths without validation: a version entry named `../..` or `/home/user/x` is deleted recursively and cloned over (`src/Build/Project.zs`) | fixed |
| R2-pkg-10 | medium | Concurrent builds share the module IR file &lt;key&gt;.ll in ~/.cache/zs/objects, written non-atomically and deleted after compiling: a truncated … (`src/Build/Units.zs`) | fixed |
| R2-pkg-11 | medium | A fetched dependency's zs.toml can crash or hang zs and the language server: heap sizes overflow (integer overflow panics), and `main` may name a … (`src/Build/Project.zs`) | fixed |
| R2-pkg-12 | medium | zs update rewrites the first "version" on a dependency's line: a URL containing that word is corrupted, and the dependency silently becomes a … (`src/Build/Project.zs`) | fixed |
| R2-pkg-13 | low | The packaged provider's binary cache key hashes only .zs files under the package main's directory: the provider's own main elsewhere, its zs.toml and … (`src/Build/Modules.zs`) | fixed |
| R2-pkg-14 | low | The lock's integrity hash is XXH3-128, a non-cryptographic hash, where proposal 0018 specifies SHA-256; for vendor/ it is the only integrity check (`src/Build/Tools.zs`) | deferred |

### Front end and zs fmt

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R1-25 | high | Integer overflow panics in the parser and checker on crafted numbers (hole width, measure exponent, fixed size) crash zs, the LSP and the build server (`src/Syntax/Parser.zs`) | fixed |
| R1-26 | high | Exhaustiveness check expands or-patterns into their full cartesian product: exponential time and memory from a short match (`src/Infer/Patterns.zs`) | fixed |
| R1-64 | medium | Range formatting deletes comment and blank lines at the edges of the selection (silent data loss in the editor buffer) (`src/Syntax/Format.zs`) | fixed |
| R1-65 | medium | zs fmt reflow is roughly cubic: each successful break resets the rejected set and re-parses the whole file several times per attempt (`src/Syntax/Format.zs`) | fixed |
| R2-leftover-0 | low | rangeFormatting with a line outside the document panics the LSP (index out of range) (`src/Syntax/Format.zs`) | fixed |
| R1-86 | low | zs fmt rewrites source files in place by truncating them first; a failed write leaves the file truncated (`src/Main.zs`) | fixed |
| R1-87 | low | `handle` used as a name inside brackets is parsed as a handler when a later `{ r with … }` appears, so valid programs are rejected (`src/Syntax/Parser.zs`) | fixed |
| R1-88 | low | A malformed or very long float literal compiles to 0.0 without any diagnostic (`src/Syntax/Literal.zs`) | fixed |

### Scripts, CI, editors

| Ref | Severity | Finding | Status |
|---|---|---|---|
| R2-leftover-13 | medium | install.sh resolves its paths against the repository root and its `&&` lists get past `set -e`: `rm -rf "$dir/lib"` deletes the repo's lib/ or a … (`src/install.sh`) | fixed |
| R2-leftover-14 | low | Release archives record the builder's uid/gid; extracting them as root leaves the compiler and runtime writable by an unprivileged account (`src/release.sh`) | fixed |
| R2-leftover-15 | low | CI downloads and runs toolchains without checksums or pinned versions (Linux arm64 LLVM and zig piped into `sudo tar`, micromamba `latest`, unpinned … (`.github/workflows/test.yml`) | partly fixed |
