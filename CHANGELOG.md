# Changelog

## Unreleased

Windows, natively: the suite runs and passes on CI's Windows x64 and arm64 runners, as on the
other four (at `be321b3`, the first run with every job green), and what it found is fixed here.

### Language
The specification's three defects (ROADMAP's track G, items 1 to 3). What a 0.7 program rewrites:
- An integer literal outside its type's range is an error at the literal, where it was
  truncated (`let a : u8 = 300` was `44`); a pattern's literal alike. A literal in a radix may
  still fill its type's bits (`let m : i8 = 0xFF`). Write the value meant, or a wider type.
  A generic function with a literal is of the types that hold it (`let f x = x + 300` isn't
  a function on `u8`), and a constant's literal is checked at each use
  (`tests/err_literal_range.zs`).
- `break`, `continue` and `return` ([proposal 0029](docs/proposals/0029-leaving-a-loop.md)):
  a loop and a function left early, with `use` values disposed on the way; `?` as a statement
  of a loop's body returns its failure from the function (it was an error there). The three
  are reserved words now (`return` outside a computation expression): a value, function or
  parameter named `break`, `continue` or `return` is renamed (`tests/loop_leave.zs`,
  `loop_leave_use.zs`, `err_loop_leave.zs`).
- `1e-3` is a float literal, as DESIGN.md said and F# reads it (`tests/float_exponent.zs`).
- `compare` is a total order on floats: a NaN is after every number and equal to a NaN, where
  `compare nan x` was `0` for every `x`, so a list with a NaN sorts and a `Map` takes it as a
  key. `=`, `<` and the other operators are IEEE 754's, as before (`tests/compare_nan.zs`).

### Security and stability
A review of 0.7.0 ([docs/reports/security-review-0.7.md](docs/reports/security-review-0.7.md))
found 106 defects (1 critical, 30 high, 48 medium, 27 low); 103 are fixed here, each with a test,
two in part and one deferred, with the designs that finish them. What a program or a user sees:
- `zs lsp` and `zs mcp` build and run a dependency's type provider only with `--trust` (the
  module from the last trusted build otherwise, or an error at the import); the VS Code and
  Rider extensions pass it in a trusted workspace or project, Zed's doesn't.
- A Buffer read in a `for` loop is bounds-checked (versioning took the Buffer's owner pointer
  for its length); `Buffer.blit`'s range doesn't wrap; `for` ends at its type's last value.
- Use-after-frees and double frees from safe code are gone: a mutable moved and reassigned
  (`Rc`), an `Spsc` popped on two threads (now any number of producers and consumers, still never
  waiting), a weak reference to an object another thread holds, a closure carrying a `ref` across
  threads (now a Share error), the runtime's `Native.*` hooks (now the library's, or `unsafe`'s).
- A literal that only a library trait constrains is an `int` (a float an `f64`), as any other:
  `Binary.toBytes 70000` took it as the first type with an impl, an `i16`, and wrote 4464.
- On a chip, a stack overflow is a panic (the stack below everything else in RAM, an MPU guard
  where there is one), and the heap masks interrupts while it changes.
- `Json` has a `JUInt` case (integers from 2^63 to 2^64 - 1): a `match` on `Json` without a
  wildcard needs it. `Json.parse` and `Binary.ofBytes` nest 32 levels where `int` is 32 bits
  (1,000 elsewhere); `Binary.ofBytesWith { depth }`. `Hmac.verify` and `Bytes.fixedTimeEquals`.
  `Iter`'s range panics on a step of 0. `Format.format` with a specifier made at run time panics
  on one a written specifier couldn't be.
- A `.bat` or `.cmd` started by `Process` gets `cmd.exe`'s quoting (an argument with a line break
  is an Error); `SIGPIPE` is ignored (a write to a closed pipe is an Error; a closed standard
  output still ends the program as it did); `File.copy` onto itself is an Error and a copy keeps
  the source's mode; `File.move` across file systems renames a finished copy over the target;
  `Directory.deleteRecursive` never follows a link; `Unix.listen` replaces only a stale socket;
  `Tcp.connect` resolves off the event loop and tries every address.
- Packages: links in a dependency are hashed as links and `zs vendor` copies only those that stay
  inside it; lock entries' names are checked; a manifest's `main` is inside its package (the
  project's own too); a `zs.toml` is at most 1 MB; a dependency's caches are in the project's
  `.zs-cache/pkgs/`, never in the dependency or through a link; a header added beside a
  package's C file, or changed anywhere it's included from, makes a new object on every target.
- The thread pool waits, rather than panicking, when a job waits on a lock or channel past its
  spare threads; the build server drops a client that stalls, and a provider program stops after
  60 seconds (`ZS_PROVIDER_TIMEOUT`); `zs fmt` writes a file whole or not at all.
- `src/install.sh` refuses a directory that isn't a compiler's; release archives are root's,
  written by no one else; CI checks the toolchains it downloads.

### Runtime
- On Windows on Arm, a subnormal `f64` prints as on every other target (`3.13983658588571e-319`,
  not `6.5205388442357377e-4932`): numbers are written by the UCRT's own printf on Windows, not
  mingw-w64's, which reads such a value as an 80-bit one where a long double is a double. A NaN
  is `nan` on every target (glibc wrote `-nan` for x86's `0.0 / 0.0`, the UCRT `-nan(ind)`).
- On Windows, `Udp.receive` cuts a datagram longer than the buffer to it, as on Linux and macOS
  (Winsock failed the receive), and `Unix.connect` to a path with nothing there fails with "No
  such file or directory" (Windows' AF_UNIX says a network is down).
- On Windows, a UDP socket's next receive no longer fails after a datagram it sent drew an ICMP
  port-unreachable (Winsock's `WSAECONNRESET`; `SIO_UDP_CONNRESET` is off), as on Linux and macOS,
  where an unconnected socket isn't told.
- On Windows, a `--coverage` program's counts are written as bytes: in text mode each line ended
  `\r\n`, which `zs test --coverage` didn't read, so it counted nothing.

### Library
- `Diagnostics.ToOutput`: a started process's standard error where its standard output goes
  (`stderr = ToOutput`, its pipe when that's `Piped`), as a shell's `2>&1`, so one reader sees
  both in order and neither fills while the other waits (`tests/process.zs`).

### Tooling
- On Windows, a build no longer waits for ever before it starts: its check for the target runs
  `zig cc -v`, whose search list on standard error filled the pipe while `zs` read standard
  output to its end (0.7.0's CI on Windows stopped there, printing nothing). The runtime's pipes
  there hold a megabyte, where Windows' default is a page or so; the compiler moves to
  `ToOutput`, which no amount of errors fills, once it's built by a release whose library has
  it (stage 0 is 0.6.1's).
- On Windows, a build with C beside it links: a `[<Link "x.c">]` source, a package's `[c]` source
  and `import c`'s, joined with Windows' `\`, were passed to zig as libraries to link
  (`-lD:\…\x.c`: "failed to check zig installation for DLL import libs"), so `import c`, the
  `libclang` and `xxhash` packages and the compiler's own build failed there.
- On Windows, the compiler's own messages name files with `/`, as git does there: a
  diagnostic's file, `built app/build/app`, `vendored text v1 into vendor/text`, `zs tree`'s
  paths, a saved failing case, a workspace's members, a provided C module's `// input:` line,
  and the language and MCP servers' messages. Programs keep `Path`'s `\`.
- On Windows, a native build runs pkg-config for a package's `[c]` as other machines' do (it was
  taken for a cross build, for the mingw-w64 triple it targets), its `\r\n` read as an end of
  line and not an argument; `zs provide` finds `zs-provider-<name>.exe` on PATH, which is
  `;`-separated there; and `zs check`, the language server and MCP read a C header as `zs build`
  does there, for mingw-w64, finding the import it saved.
- The language server on Windows reads the URIs editors send, `file:///C:/a` and VS Code's
  `file:///c%3A/a`, as `C:\a` (it took the drive for a directory, `\c\a`, and opened nothing),
  and writes them back as `file:///C:/a`, with `/` and the drive (RFC 8089); renaming a provided
  name is refused there too. The MCP server's tools reach the project's files on Windows (each
  was "outside the project"), and `build` and `run` build for mingw-w64 as `zs build` does.
- `zs test`, a test run on a chip, MCP's `run` and git dependencies start their programs
  themselves, with no `timeout` or `env`: a test's time limit is the compiler's (killed then,
  reported as before), and its variables are added to the environment it passes on. A stock Mac
  has no `timeout`, and on Windows outside Git Bash `timeout` is another program, so every test
  failed there. Both output streams are read while the program runs, so one filling its pipe
  doesn't wait for its time limit (MCP's `run` read standard output to its end first).
- On Windows, `zs build` runs each build in its own process, with no build server: whoever
  reaches the server's socket runs `zs` as its user, so its directory must be that user's alone,
  and Windows' `chmod` sets nothing (the directory kept the ACL it inherited).
- A debug build for Windows is the same bytes each time, as a release build was: the link wrote
  the time into the PE header (`/Brepro` puts a hash of the binary there instead). Its debug
  info's directories are escaped as LLVM reads a string (`tests\debug` read as the byte 0xDE).
- `--profile-generate` and `--profile-use` are refused for a build zig links (another target,
  and mingw-w64 on Windows), whose link has no profile runtime: it built a program that wrote no
  profile.
- A git dependency is checked out with its files as committed on every OS (`core.autocrlf=false`,
  `core.eol=lf`), so `zs.lock`'s hash of them is the same on Windows.

### Documentation
- [The language specification](docs/spec/README.md): the language's definition in 14 chapters,
  from the lexer's rules to the grammar, with what's planned, where the compiler deviates from
  the design (an integer literal too large for its type is truncated, not refused; `1e-3` isn't
  a float literal) and what was declined.
- The README is shorter and by reader: F# programmers, systems programmers, embedded developers,
  with a section on status and limitations; the full tables stay in `docs/reports`.

### Tests
- The suite runs natively on Windows (CI's x64 and arm64 runners): text is checked out with LF
  there too (`.gitattributes`; git for Windows' CRLF failed every comparison), each test program
  is stopped after 600 s instead of holding up the rest, a C program linking a Z# library uses
  zig's MinGW target as `zs` does (clang alone targets MSVC, which has no `libm`), and the
  architecture is the machine's (Git Bash runs as x86-64 on Windows on Arm, its `uname` saying
  so: `PROCESSOR_IDENTIFIER` doesn't).
- CI on Windows: LLVM 23.1.4, the other runners' version, from LLVM's release (Chocolatey's
  package is the x64 build on Windows on Arm too, whose libclang an arm64 `zs.exe` can't load,
  and Windows x64's image had LLVM 20); zig 0.17.0 from its release (0.16.0's `zig rc` failed
  every build on arm64); pkg-config; a first build of one program with each step bounded; and a
  job stopped after three hours.
- The programs that wrote under `/tmp` use the temporary directory (`Directory.temp`), which a
  native Windows program has, and `tests/process.zs` checks a process's directory by what's in
  it, not by `pwd`, which on Windows names `/` as the drive's root (`/c`, `/d`).
- On Windows, the scripts strip a temporary directory as the compiler is handed it (Git Bash's
  `C:/…/Temp/…` for `/tmp/…`), `tests/providers/provide.sh`'s provider on PATH is a Z# program
  (Windows starts no script), a guide example's output on Windows is a ```` ```text windows ````
  block after its own (`tests/docs.sh`), and `tests/providers/svd_nucleo.sh` is skipped where
  there's no `opt`.
- The language and MCP servers' scripts give `zs` Windows' own paths there (`cygpath -m`: Git
  Bash's `/d/a` reaches only its own programs), and `tests/lsp/providers.sh` writes to the server
  through a pipe, not a named one, which `zs.exe` reads nothing from. `tests/server.sh` is
  skipped on Windows, which has no build server.
- gdb's checks run on Windows x64: their commands are a file (`-x`; a native gdb started from
  Git Bash got each `-ex` split at its spaces), Windows' "Thread 1 hit Breakpoint 1" reads as
  Linux's "Breakpoint 1", a backtrace is checked for its Z# frames (below them the C start-up's
  are the platform's), the build is bounded at 5 minutes (a first `-g` build there fills zig's
  cache), and where one fails there gdb's own output follows (`GDB_RAW=1`). They're skipped on
  Windows on Arm, whose gdb is x86-64's.
- `tests/libm.sh` links with the Windows-aware C compiler, counts a zero's unit as the smallest
  subnormal (the UCRT's `atan2` flushes a result just past half of it to zero, where ours rounds
  to it: 1 ulp, not a difference in kind), and names the worst arguments when past its bound;
  `tests/project/git.sh`'s repositories keep LF.

## 0.7.0 (2026-11-05)

The second public release: what the flagship and the first users asked for, from 0.7's plan
(ROADMAP), without that plan's first item, the checks on machines (below). The compiler is fuzzed in
every run of the suite (the same 300 programs each time) and builds programs as long and as deep as
generated code writes them; a stack overflow is a panic, a throw disposes the `use`s it passes over,
every value has debug info, and `-g` keeps the lines of an optimized build. Two memory errors 0.6.2
had are fixed: a value lent to a read or a call that another of its arguments freed first, and a
weak reference taking a later object for the one it pointed to. For the chip: constants in flash,
values placed in named sections (`.noinit`, a DMA region), fixed-point numbers, weak references and
arenas, and a file's tests run on it. Beside them: type providers (JSON, CSV, SQL, SVD, C headers
and providers of your own), properties with shrinking and `zs fuzz`, `zs bench` and `zs test
--coverage`, workspaces, `zs vendor` and a lock that hashes its dependencies, and track S's small
items (`Int`'s checked, saturating and bit operations, ISO 8601, UDP and name lookup), with ten
Advent of Code puzzles and three small tools as its exit tests.

Archives for Linux, macOS and Windows on x86-64 and arm64, each built on Linux x86-64 by
`src/release.sh`, whose compiler builds itself to the same bytes. Linux x86-64's suite passes in
the dev container (Fedora 44, LLVM 23), the chips' programs under QEMU and wasm32's under Node
among it, `tests/pgo.sh` and `bench/host` too. On Ubuntu 24.04 those two fail on that machine's
tools: `tests/pgo.sh` on LLVM 20's profile runtime, and `bench/host`'s `fib` at 5.3% over its
instruction baseline (2,464,794 against 2,339,907, past the 5% the check allows). CI's Linux x86-64 job, in the dev container, failed two more on 2026-11-05, both fixed
here: `tests/debug/kinds.zs`, whose DWARF LLVM 23's `llvm-dwarfdump --verify` rejected for a
`.debug_str_offsets` entry inside a string GNU ld had merged by its tail (the one error the check
now lets by; lld's output has none), and the tree-sitter grammar, which didn't parse a typed `_`
parameter (`let check () (_: Source)`). What 0.7's plan put first is undone (ROADMAP, 0.7's item 1):
the flagship isn't flashed to a Nucleo-F401RE yet (it runs under QEMU's STM32F405, which models none
of the board's GPIO), the suite hasn't passed on the five CI runners (at `fbf956d`, on 2026-11-05,
Linux x86-64's passed and the others' failed: 23 and 24 checks on the Macs, the same 7 as before on
Linux arm64, and the Windows suites printed nothing; what the Macs and Linux arm64 failed on is
addressed after it, not yet confirmed in CI), and no archive has been tried on a clean machine, so
no macOS or Windows build has run on a real machine. Linux arm64's suite under QEMU and Windows
x64's under Wine, which 0.6.2 ran, haven't been run for 0.7, nor has the stress run over the pool,
tasks and `Alt` under ThreadSanitizer (the suite's four programs under ThreadSanitizer pass). Of the
plan's other items, the fuzzer's seed isn't rotated per run yet (it's 1 unless `ZS_FUZZ_SEED` says),
and `[<Align>]` on a type, `Seq` pipelines as one loop (track S, item 9) and fixed point's vector
forms are left.

### Upgrading from 0.6.2
What a 0.6.2 program, project or script may have to change, and what behaves differently:
- A negative integer literal is a signed integer: `let a : u8 = -1`, a `-1` passed where a `u8` is
  wanted and a pattern `| -1` at an unsigned type are errors (`expected u8, got int`; `a negative
  pattern is a signed integer; u8 has no -1`), where 0.6.2 negated the positive literal at run
  time, which overflowed, and matched a pattern's value wrapped to the type with nothing said
  (`| -1` at `u8` matched 255). **To rewrite:** the value itself (`let a : u8 = 255`, `| 255`).
- A one-case union over plain values has no tag (decision 66): `type UserId = UserId of int` is
  an `int`, 8 bytes on a 64-bit target, where 0.6.2 put a 4-byte tag before it (16), so `sizeof`
  and `alignof` give its field's, and the records and arrays holding it are smaller. **To
  rewrite:** an `assert` on such a size.
- A throw, or a handler clause that stops without resuming, runs `Dispose.dispose` on what the
  `use`s it passes over bound, newest first, before the clause runs; 0.6.2 freed them without it.
- A stack overflow on Linux and macOS (in a program, not under a sanitizer) is a panic,
  `panic: stack overflow (recursion too deep)` with exit status 134, where it was a SIGSEGV (139
  in a shell).
- A dependency's module under a directory named `internal` (at any depth, in either case) is the
  package's own: naming it from another package is an error that lists the package's public
  modules. **To rewrite:** the import, to one of those.
- `zs.lock` gains a hash of each git dependency's files at the next build or fetch (a 0.6.2 lock
  is read as it is, and rewritten then). From then on a checkout edited under `.zs-cache/deps/` is
  restored from its commit at the next build, and one that still differs is an error. **To
  rewrite:** a dependency patched in place, as a path dependency (`zs add ../json`).
- `Testing.Test` has two more cases, `Bench` and `Property`. **To rewrite:** a match over a
  `Test` (a runner of your own), with their arms or `| _ ->`. A test binary's `--list` gives a
  fifth field, the entry's kind (`test`, `bench` or `property`).
- With `ZS_LEAKCHECK=1`, a test that leaks at its exit fails under `zs test`; 0.6.2 reported the
  leak and passed it.
- `zs build -g --release`, and `-g` with any `-O` level, is an optimized build that keeps the
  lines; 0.6.2 built it at `-O0`. `-g` alone is still `-O0` but on the Cortex-M0+ and wasm32,
  where it's now the optimized build with lines.

### Language
- A negative integer literal is one constant, a signed integer: `i32 -2147483648` on a 32-bit
  `int` target (a chip) was the positive literal, past the type's range, negated, and panicked
  with an overflow (`tests/mcu/ints.zs`). So `let a : u8 = -1` is an error (it overflowed at run
  time), and so is a pattern `| -1` at `u8`, which says so; `-0x8000_0000_0000_0000` is i64's
  least, as a value and as a pattern (`tests/err_neg_unsigned.zs`, `tests/err_neg_pattern.zs`,
  `tests/fold_edges.zs`).
- One-case unions without a tag (decision 66, built): a plain union with one case that has
  fields is the field itself (`type UserId = UserId of int` is an `int` in registers, arrays and
  records; `sizeof<q15>` is 2), or a struct of its fields; matching, equality, show, hash and
  the debug info follow (`tests/onecase.zs`). One over a heap value (`Wrap of string`) stays
  boxed, its count in the object. A `[<CLayout>]` record can't hold one yet (C's view of a
  one-case union is left).
- F#'s list and array ranges: `[ 1 .. 10 ]`, `[ 1 .. 2 .. 9 ]` (a step, negative too) and
  `[| 0 .. n |]`, the list expression over the range, so one loop and the list built once, empty
  when the range is (`tests/ranges.zs`). The README called them not there yet.
- Typed tuple parameters as F# writes them: `let f (a: int, b: string) = …` is one parameter of
  type `int * string`, called `f (1, "x")`; each part takes its type (the error says so when one
  is missing). The other not-there-yet of the README.
- `use` under effects (track S, item 10): a throw, or any handler clause that stops without
  resuming, disposes what the `use`s it passes over bound, newest first, before the clause runs,
  as a cancelled task does (`tests/effects/use.zs`). It freed them without their `Dispose.dispose`.
  Code without effects compiles exactly as before. A resumption a clause keeps and never calls,
  and a stop inside a `task { }` body, still dispose nothing; a consumer that leaves a generator
  early (`Seq.take`, `Seq.tryFind`) stops it, and that disposes.
- `[<Section ".noinit">]` and `[<Align 32>]` on a top-level value (0014 item 12, decision 69):
  a constant table, `Buffer.create n x` or `ref x` with constant arguments has its storage in
  the image, in the named section and so aligned (a table's data at a multiple of it after its
  header), with no startup code and nothing allocated. `.noinit` is neither copied nor zeroed by
  the chip's reset handler (`runtime/boards/cortex-m.ld`), so a boot counter or a crash log
  survives a reset; a push past a placed Buffer's room moves it to the heap and leaves the
  storage. On a function, a computed value or an alignment that isn't a power of two from 8 to
  4096, an error says what the attribute takes. A section named `.noinit…` (as the boards'
  scripts' `*(.noinit*)` takes it) holds a ref or Buffer of plain values only (a string or array
  there would point into memory a reset left), and not a constant (never loaded); a section's
  name is letters, digits, '.', '_' and '$'. The element may be any constant (a fixed-point
  number, a tuple, an option, a table), its own objects constants outside the section. On a
  chip, a ref's or Buffer's storage in a section the board's script doesn't name (a DMA region)
  is copied from flash at startup; a constant table alone in such a section is read-only and
  stays in flash, but one sharing it with a ref or Buffer (RAM, never loaded) or in `.bss…`
  (zeroed) is an error, as is a ref or Buffer in flash (`.text…`, `.rodata…`) or one in `.bss…`
  that doesn't start at zero (a plain union's first case does), and anything in the board's own
  `.vectors` or `.ARM…`. A chip's library has no startup, so its placed values mustn't need that
  copy or a `.noinit` ref's header (a host's or wasm32's loads its sections like any other). A
  placed Buffer's slots are dropped at exit whatever it did since (written, grown into the heap,
  shortened). A program with placed values builds as one module, so they're placed wherever
  they're declared (`tests/placement.zs`, `tests/placement_drops.zs`, `tests/err_placement.zs`,
  `tests/mcu/placement_errors.sh`; on both chips, a boot counter across SYSRESETREQ resets under
  QEMU, `tests/mcu/noinit.zs`, `tests/mcu/sections.zs`, and with `--no-heap`,
  `tests/mcu/noheap_placed.zs`). On macOS, where Mach-O names a section
  `segment,section`, the name is dropped and the alignment kept, as on Windows (it was emitted,
  and stopped clang's backend). `[<Align>]` on a type is left.
- Writing a Buffer's element is no allocation for `[<NoAlloc>]` and `--no-heap` (it was taken for
  an array's copy-on-write), and the write borrows the Buffer as a read does, so writing a
  parameter's, a field's, an element's or a top-level Buffer frees nothing; the element it
  overwrites is a drop when its type is counted, and so is a Buffer a call gave or a mutable
  moved into the write, or one taken out of a value the write frees: a write is accepted only
  where the Buffer is provably held elsewhere (a variable's, a top-level value's, a field's or an
  element's), on every path of a match or an if (`tests/noalloc.zs`,
  `tests/err_noalloc_buffer.zs`, `tests/err_noalloc_buffer_call.zs`,
  `tests/err_noalloc_buffer_taken.zs`, `tests/err_noalloc_buffer_arms.zs`,
  `tests/err_noalloc_buffer_alias.zs`).
- A library (`--lib`) may hold top-level constants: a table, a record, a tree of union cases
  are static objects with no startup code, which a library doesn't have; only a value really
  computed at startup is an error, from the code generator, and so is a startup assert
  wherever it is among the values. Whether a value is a constant doesn't depend on the build:
  `-g` and `--coverage` keep the code as written, but a value whose initializer folds to a
  constant (`[| 1 + 2 |]`, `[| Q15.ofFloat 0.5 |]`) is that constant there too
  (`tests/libstatic.zs`, from C, with `-g` and `--coverage`).
- `module Weather = import json "weather.json"` and the bare `import csv ("stocks.csv", separator = ";")`
  (0001): the provider's module, written to `.zs-cache/providers/<importing module>/<Name>.zs`
  and loaded as a dependency of the file, so `Weather.Root`, `Weather.parse` and hover, definition
  and completion on them are a module's; the bare form opens a hidden module named after the file
  and the provider (`StocksCsv`), so `Row`, `parse` and `print` are in scope, the module's own
  names before the prelude's. Options are constants after the string, in a member call's syntax.
  An import of a provider zs doesn't have, a file that isn't beside the importing file, or an
  option the provider doesn't take is an error at the import. In the editor the types follow
  the sample: the language server watches the files providers read and re-checks the documents
  made from one that changes, and a rename of a provided name says where it comes from
  (`tests/providers/import_use.zs`, `tests/lsp/providers.sh`).
- `import sql "schema.sql"`: a record per `CREATE TABLE` (`INTEGER` `int`, `REAL` `f64`, `TEXT`
  `string`, `BLOB` `array<u8>`, `BOOLEAN` `bool`; a column an option unless `NOT NULL` or in the
  primary key) with `table` and `columns` in a module of its name. `import svd ("chip.svd", only =
  "GPIOA,RCC")`: a module per peripheral, each register a `[<Bits>]` record whose defaults are
  its reset value and a module with `read`, `write` and `modify` as the file allows;
  `examples/mcu/nucleo-f401-svd.zs` is the Nucleo firmware on the STM32F401's SVD, compiled to the
  same register accesses as the one with addresses by hand (`tests/providers/sql_use.zs`,
  `tests/providers/svd_use.zs`, `tests/providers/svd_nucleo.sh`).
- Providers of your own: `zs-provider-<name>` on PATH, run in the importing file's directory
  with the string and `--name=value` options, its standard output the module (`// provided by`,
  `// input:` lines first), its standard error the errors. The output is cached with a hash of
  each input, so a machine without the provider builds from the last output, with a `stale-input`
  warning at the import naming an input that changed since. A dependency package with a
  `[provider] main = "Main.zs"` section is the provider of its name: the compiler builds its
  program into `.zs-cache/providers/bin` when its sources change and runs it the same way
  (`tests/providers/pkg`, `tests/providers/shout`). `examples/providers` and the guide's chapter
  18 show all of it.
- `import c` on the providers' protocol: `module Ray = import c "raylib.h"` is the header's
  declarations as a module, each with its C signature and comment as its doc, and
  `zs provide c raylib.h` prints that binding as Z# to keep (externs, `[<CLayout>]` records and
  unions, constants from macros; the names left out listed with why). The bare `import c` keeps
  its path, `[<Link>]` and the editor's C hover (`tests/providers/cshapes`).
- `sql`'s `queries = "queries.sql"`: named queries (`-- name: GetUser :one` before each, as sqlc
  writes them) as a module each, typed against the schema: the text with `?` for each parameter,
  the parameters' names, a `Params` record typed from the columns they meet (compared with, or
  inserted into by position), and a `Row` record for a select's columns (`SELECT *` a table's,
  a join's by table or alias, an expression `AS name`). A column or table not in the schema is an
  error naming the query (`tests/providers/sql_queries_use.zs`).
- `M.f` names the extern `f` declared in module `M` (a C function is one global name, and was
  reachable only bare): `Shapes.rect_area` on a `module Shapes = import c "shapes.h"`
  (`tests/providers/cshapes`).
- `svd`: a field's enumerated values that are 0 to n-1 are a union of cases, named after the list
  (`Value` added when a register's record has the name), shared by the fields with the same
  values; sparse values stay a number (`tests/providers/svd_enum_use.zs`).

### Compiler
- Constants folded (0015 step 4): arithmetic, comparisons, bit operations, conversions and
  `Math.round` and `sqrt` on literals are computed at compile time, as the code would compute
  them, and a `let` of a float literal puts the literal in its uses; an integer result that wouldn't
  fit its type stays as written, to overflow at run time (`int` taken as 32 bits, a chip's).
  Integers fold only when they're values of their types (a `u64` at or above 2^63 isn't folded
  with signed arithmetic), `f32` is rounded to single precision at every step, the sign of zero
  is kept (`-0.0`, `Math.round -0.3`), a NaN result isn't folded, and a conversion nested in
  another wraps as the code does. A static's `f32` literal is single precision (so widening it
  is exact), and an `int` or `usize` past 32 bits converted to a wider integer or a float is
  left to the code, as a chip wraps it. A match with a pattern literal, at any depth, that isn't
  a value of its type (`| Some 256` at `option<u8>`) is neither decided at compile time nor made
  a decision tree, so the code's comparison at the type's width decides it, in order. So
  `Q15.ofFloat 0.5` is a constant once inlined, and a table of them a static object
  (`tests/fold.zs`, `tests/fold_edges.zs`, `tests/static.zs`).
- Constants in flash, the rest of item 3 (0014): a top-level record, tuple or plain union of
  constants is written into its global, a boxed union case (a tree's node) is a static cell, and
  they nest any way (an array of records, a list of shapes, a record holding a table). A boxed
  case of constants was a constant built at each use and is a value now, so it's static too.
  Nothing of these runs at startup (`tests/static.zs`, `tests/mcu/static.zs`).
- Constants in flash (0014, item 1, for arrays and lists): a top-level array or list literal of
  numbers, bools or strings is a static object in the image (count 0, never unique: a write
  copies it), the value's global pointing at it, with no startup code and no heap; on a chip its
  bytes are in flash (`tests/static.zs`, `tests/mcu/static.zs`: three tables on a Cortex-M4, 64
  bytes of heap and three allocations gone, and the image 496 bytes smaller without their
  startup code). `--no-heap` takes such a value.
- A union with a case holding a list of itself (a tree) builds for the Cortex-M0+: its drop
  function's last call is a plain call there, where Thumb1 can't tail-call another function (a
  loop still, as a list's drop is a call to itself); LLVM refused the image before
  (`tests/mcu/tree.zs`).
- A record field's default resolves its names in the record's declaring module, not where the
  record is built: a provided register's `mode0: ModeValue = Alternate` holds for a literal in
  another module (it was "unknown name 'Alternate'" there; `tests/providers/svd_enum_use.zs`).
- Long and deep programs, as generated code writes them, build: a flat list literal of 20,000
  elements, 10,000 statements or `let`s in one function, an `else if` chain or nested parentheses
  10,000 deep each crashed the compiler (its stack overflowed); its threads now have 256 MB of
  stack where the system's hard limit allows, and the pool's threads the soft `ulimit -s` when
  that's over 8 MB (`tests/stress.sh`).
- Nothing quadratic in what was: an array literal of 100,000 elements checked in over two minutes
  (each element's type variable was bound to the one before, and unification walked the whole
  chain: variables are now bound straight to the end of a chain once it's walked, trailed so a
  trial undoes that too), 2.4 s now; a chain of 1,000 small functions, each calling the one
  before, took over a minute to inline (each copy carried every one before it, and whether a
  function could reach itself was a walk per function), 1 s now. A copy inlined carries at most
  four times a small body, so twelve of the test programs compile to up to 38% less IR, running
  the same.
- A type with a member declared twice, or a member named as one of its fields, and a call to one
  of its members crashed the compiler (`panic: Map.find: key not found`; `tests/fuzz.sh`'s seed 1
  found it): the member that can't be is reported and left out, and the type's other members
  stand, so the call checks. A call to a member whose function never got defined is an error
  naming it, never a crash (`tests/err_member_twice.zs`).
- A UTF-8 byte order mark at the start of a file is skipped, as `\r\n` is read as `\n`; it was
  "expected 'let'" (`tests/stress.sh`).

### Runtime
- A panic's backtrace names the Z# functions on the way (0011, debugging 5), the runtime's own
  frames left out and the program's `main` last: on Linux the runtime reads the executable's
  own symbol table at the panic (a build keeps it; the functions are internal, so nothing else
  names them), in release builds too, and names the function of each call (not the one after
  it). On macOS, and in a library built into a C program, it's the C library's symbolizer, as
  in 0.6.2. `ZS_BACKTRACE=0` keeps the panic to its message, as before (`tests/backtrace/run.sh`).
  Lines need `-g`'s DWARF and are left.
- Weak references and arenas on a chip (track M, item 8, known gap 3): the embedded runtime
  has the host's table of weak cells and its arenas, over the chip's heap. An arena's blocks are
  an eighth of the heap each (4 KB at most), bumped through, and go back at once when the
  arena's last object has died; an object's arena is found by its address among the blocks. The
  table and the blocks are heap memory, not objects, so the exit report's `live` stays the
  program's. Released blocks are kept for arenas (on the heap's list of large blocks any object
  over 256 bytes would take a whole one), but a larger freed block an arena took goes back to
  the heap when it's released, and the heap takes the arenas' blocks back before it runs out;
  a block is a multiple of 8, so a heap size that isn't a multiple of 64 keeps the heap aligned
  (`tests/mcu/weak.zs`, `tests/mcu/arena.zs`, `tests/mcu/arena_rounds.zs`,
  `tests/mcu/arena_big.zs`, `tests/mcu/odd_heap.sh`, both chips).
- Panics on several threads at once give one report: the others wait for its stop, and a panic
  inside a panic stops at once (`tests/backtrace/run.sh`: four threads at once). A panic's
  message is printed by its length, so a NUL in it doesn't cut it short.
- A stack overflow is a panic: `panic: stack overflow (recursion too deep)`, exit status 134, what
  was printed before it flushed, on whichever thread overflows (the pool's, a task's loop's;
  two at once say so once). It was a SIGSEGV with nothing said. On Linux and macOS, in programs
  (a library leaves its C host's signals alone), not under a sanitizer, which reports one itself
  (`tests/panic_stack_overflow.zs`, `tests/panic_stack_overflow_thread.zs`).

### Security
- A value reached through a pattern variable is lent to a read, to a call that borrows it or to
  a closure's application only when no other argument takes the value it was matched from: one
  that did (handing it to a function that frees it) freed it before the read or the call used
  it, in 0.6.2 too. And a `let mutable` passed to a function that borrows it, which another
  argument reassigns, is read where it stands, the arguments bound left to right, and kept alive
  through the call; the assignment freed it first (`tests/buffer_lend.zs`, clean under valgrind).
- A weak reference to an object the runtime frees itself (a weak cell, an `Spsc`, a `Channel`)
  sees it die: those frees go through the checked path, so a later object at the same address
  isn't taken for it (`tests/weak_runtime.zs`; on both chips, `tests/mcu/weak_runtime.zs`).

### Library
- Properties (0010, track D item 5): `testProperty "name" (fun (xs: list<int>) -> …)` runs
  the property on 100 cases drawn with `Arbitrary` at the parameter's type (a tuple for
  several), growing from size 0 to 100; `unit`, `true` or `Ok` passes a case, `false` or an
  `Error` fails it, and the failing case is shrunk to a smallest one (its bytes shorter, then
  smaller, as Hypothesis shrinks) and shown with the seed that replays the run through
  `testPropertyWith { seed = Some s }`; `{ runs; maxSize; maxDiscardRatio; shrink }` are the
  other settings. A generator (`Gen<'a>`) reads a stream of bytes, so every one shrinks:
  `Gen.int ()`, the sized integers, `float`, `bool`, `char` and `string` (each a function of
  unit), `range`, `elements`, `frequency`, `oneOf`, `map`, `bind`, `filter`, `list`, `array`,
  `listOfLength`, `option`, `sized`, `scale`, `constant`, the `gen { }` builder, and
  `Gen.sample seed n g` to look at one. `Arbitrary` has impls for Core's types, lists, arrays,
  options, results and tuples, and `[<Derive(Arbitrary)>]` for records and unions: a union's
  cases are ranked by how readily a value ends (0 when no field can hold the type, 1 when only
  lists, arrays and options do, which are empty at size 0, 2 when only a type parameter might, 3
  when a field is or reaches the type), drawn in that order, and at size 0 or past a replayed
  stream's end the lowest rank's with the fewest fields are the only choice. So a tree whose
  leaves carry values, one with a way out through a list, and a generic one (`Expr<'v>`'s
  `Lit of 'v`, a `Labeled<'a>` holding the type) end; a type whose every case holds it outright
  (through a `result`, say) may not past a replayed stream's end, and a generic union's
  type-parameter cases come after those that hold nothing and before those that hold the type
  (the derives gain `Shape.cases`, each case's `rank` among its facts). `Gen.option` is `None`
  at size 0; `Gen.range` spans all of `int` without overflowing and
  `Gen.frequency` sums its weights in u64; and `Gen.char` draws any scalar value but a
  surrogate, the controls last, so a case shrinks to a printable one
  (`tests/property/recursive.zs`). `prop { let! x = Gen.int () … do! Prop.assume (y <> 0)
  … return … }` draws as it goes, discards a case (`Prop.assume`) or labels it (`Prop.label`,
  `classify`, `collect`): a passing property reports how its cases were labelled, a failure
  shows the failing case's labels. `Prop.model commands { init; step }` checks a system
  against a model with a derived sequence of commands, which shrinks to the fewest with the
  smallest arguments. Under `zs test`, a case that panics is recorded as drawn (each case from
  its own seed), shrunk by replays of the test binary (`--replay`) to a smallest case that
  still panics, shown, and saved beside the file in `.zs-cache/failures/<file>/`, keyed by
  the test file and the property's path; the next run replays it first, and once it passes
  it's deleted. A panic the case doesn't reproduce alone, and a run that gave up on its
  discards, are reported as they happened, nothing shrunk or saved; a shrink keeps the failure
  it started with (its panic or sanitizer report with its values left out, an assert's place and
  the function it panicked in kept; a program's own case names count as the message's words, as
  `Some`, `None`, `Ok` and `Error` don't), so a candidate that trips another bug, another assert,
  or ends in a stack overflow, isn't taken (`tests/property/basic.zs`, `tests/property/labels.zs`,
  `tests/property/model.zs`, `tests/ztest/property.sh`).
- `Numerics.Fixed` (0015, track M item 10): `q7`, `q15` and `q31`, each a one-case union over
  its integer (its size, by decision 66), with saturating `+`, `-`, `*` (rounded half up), `/`,
  `%` (computed wider, so `min % -step` is 0) and negation, `mulAdd`, `abs`, `clamp`,
  `ofFloat`/`toFloat`/`toF32`, `ofInt`, `raw`/`ofRaw`, the conversions between the formats, and
  `Show` as the decimal with the digits the format needs (`0.99997` for `Q15.max`), in integer
  arithmetic. `List.sum` over them saturates like `+`. `Q7` and `Q15`
  compute in 32 bits, the chips' word, their products and quotients `[<Wrapping>]` (they can't
  overflow): `bench/mcu/firq15.zs`, a 32-tap `q15` filter, executes 1.05 times the instructions
  of C in CMSIS-DSP's style on the Cortex-M4 and 1.01 times on the Cortex-M0+, at `-O2`. `ofFloat` on a literal folds to a constant
  (Compiler, above); the vector forms are left (`tests/fixedpoint.zs`, `tests/panic_fixed_div.zs`,
  `tests/mcu/fixed.zs`).
- `Net.Udp` (track S, item 8): `Udp.bind host port` (0 for a port the system picks, `Udp.port`
  says which), `Udp.send` and `sendText` to a host and port, and `Udp.receive`, which gives the
  bytes (a longer datagram cut to the buffer) and the sender's address and port, each waiting on
  the event loop as `Tcp` does; `use` closes the socket. `Dns.lookup host`: a host's addresses,
  looked up off the loop's thread with `Task.blocking`, an empty list for a name that has none
  (`tests/task/udp.zs`).
- `DateTime.parseIso` (track S, item 6): the moment ISO 8601 writes, `2026-11-04T08:30:00Z`, with
  a fraction (`.25`, to nanoseconds), an offset (`+02:00`, taken off) or no zone (UTC), without
  the seconds, or a date alone, a space for the `T` too; `None` for anything else, a day its
  month hasn't and a year outside 1678 to 2262 included; a moment after
  2262-04-11T23:47:16.854775807Z, past what an `i64` of nanoseconds holds, panics with an
  overflow instead. And `DateTime.ofParts year month day hour minute second nanos`, `None` out
  of range, with the same exception (`tests/datetime.zs`).
- `Int`'s checked, saturating and bit operations (track S, item 3): `Int.checkedAdd`, `checkedSub`
  and `checkedMul` give an `option`; `saturatingAdd`, `saturatingSub` and `saturatingMul` stop at
  the type's bounds; `popCount`, `leadingZeros`, `trailingZeros`, `rotateLeft`, `rotateRight` and
  `byteSwap` are the bit operations, on `int` and every sized integer, an instruction each where
  the target has one (`CLZ`, ARM's saturating `QADD`), on the chips too (`tests/int_ops.zs`; on
  both chips, `tests/mcu/ints.zs`).

### Packages
- On a file system that ignores case (macOS's), a package's module under `internal/` is found: the
  resolver tried `Internal` first, which exists there for `internal/` too, and then refused it, so
  a path dependency whose modules use its own internal ones didn't build.
- Workspaces (0018, item 8): `[workspace] members = ["app", "libs/*"]` in a root `zs.toml` (a
  pattern ending in `/*` takes the directories under it that have a `zs.toml`). Its members
  resolve together into one `zs.lock`, one `.zs-cache/` and one `vendor/` at the root; a lock
  inside a member is an error naming the root. `zs build`, `zs test`, `zs fetch`, `zs update`,
  `zs tree` and `zs vendor` at the root run over every member (a library member isn't built on
  its own); `zs run`, `zs add` and `zs remove` there say to run them in a member
  (`tests/project/workspace.sh`).
- `zs.lock` hashes each git dependency's files (0018, item 6): a checkout that was edited is
  restored from its commit at the next build or fetch, and one whose files still differ is an error
  naming it (`zs update` accepts the new files). `zs vendor` copies the dependencies into
  `vendor/`, where the project reads them from and never fetches, their hashes checked; `zs
  build --offline` (any command's `--offline`, or `ZS_OFFLINE=1`) is an error instead of a
  fetch. `zs new` puts `.zs-cache/` in `.gitignore`. The hash is the compiler's xxhash until
  stage 0's library has `Sha256` (`tests/project/vendor.sh`).
- `zs add ../text`, `zs add https://…/json.git@1.2` (a release) or `@v1` (a rev), `--rev main`:
  the dependency written into `zs.toml`'s `[dependencies]` (the name from the package's
  `zs.toml`, or the URL's last part) and fetched; `zs remove json` takes one out, the lock
  rewritten, naming the ones there when it isn't; `zs tree` shows the dependencies as resolved,
  each with its version, where it comes from and its locked commit, its own under it (0018,
  item 7; `zs add json@1.2` by name waits for the index; `tests/project/pkgs.sh`).
- Internal modules (0018, item 3): a file under a package's `internal/` directory (any depth)
  is for the package's own files; from another package its name is an error naming the package
  and its public modules. A module's directory may start in lower case now (`internal/` for
  `Internal`), as a file could.
- A microcontroller build names a dependency that uses Std when it starts (0018, item 5):
  `package 'logger' uses File, part of Std, which needs an operating system; a build for
  cortex-m4 has none, so it can't depend on this package`, instead of an error deep in its code.

### Tooling
- Completion in the language server lists what a program declares, not only its functions and
  types: effects and their operations, traits, type aliases, union cases and modules, with a
  declaration's `///` comment as its documentation; a library module's private names are left
  out. After a module's name and a dot (`Weather.`, `List.`, `Collections.List.`) it lists that
  module's members, a provided module's among them (`parse`, `print`, `Root` for a JSON sample),
  where it listed nothing (`tests/lsp/providers.sh`).
- On macOS, `zs fuzz` links libFuzzer's runtime for macOS (`libclang_rt.fuzzer_no_main_osx.a`) and
  libc++, and `zs build --lib -o x.so` leaves a function the program defines (an `extern` of the
  library's) to the loader, as ELF's linkers do (`-undefined dynamic_lookup`): the one found
  nothing, the other didn't link.
- `zs --version` prints the compiler's release, and the language and MCP servers report it in
  `serverInfo` (they said `0.4`); `test.sh` checks it against `src/zs.toml`'s.
- `zs build -g --release` (and `-g` with any `-O` level; 0011, debugging 3): the optimizer runs
  and the DWARF lines stay, so gdb and lldb break on a line of an optimized build and show its
  backtrace with Z# files and lines; a value the optimizer keeps is shown, an inlined call's
  lines are its caller's frame's. `-g` alone is `-O0` with the code as written, for stepping,
  on every target (a chip's `-O2` default included) but the Cortex-M0+ and wasm32, whose `-O0`
  can't lower Z#'s tail calls: there `-g` alone stays the optimized build with lines. Code as
  written is what `[<NoAlloc>]` checks then, so a function passing a lambda to a library's
  higher-order function may need `-O2` (`tests/debug/opt.sh`, `tests/mcu/stepping.zs`).
- Debug info for every value (track D, item 1, known gap 4): a list, array, boxed union, `ref`
  or `Buffer` has its type's name over a pointer to its object, so gdb's `print *xs` shows a
  cell's count, head and tail, an array's count, length and elements, a node's case (where the
  cells carry one) and each case's fields over the cell, a ref's value; an option over a string
  is the string's pointer, a closure or one of the runtime's cells an address, and a `fixed` an
  array. Nothing is left out of `info locals` for its type now, and a type that holds itself
  through a list, a ref or an array is described once; a SIMD vector has no DWARF type of its
  own, but its size lays out the fields after it, as each target aligns it (`tests/debug/gdb_heap.sh`,
  `tests/debug/kinds.zs`, whose DWARF `llvm-dwarfdump --verify` checks).
- `zs test --coverage` (track D, item 10): the test binary is built with a counter per line of
  the file's directory's sources (`--coverage` on any build: the program writes the counts to
  `<program>.zscov` at exit, a panic's included), and the command reports the lines run and
  not run per file, with the runs of lines not run, and writes `coverage.lcov`, which `genhtml`
  renders and coverage services read. Match arms, branches and loop bodies count by their
  lines; the counters are atomic, so threads count right. A generic function's instance counts
  its definition's line, so one defined in another module and run isn't listed as never run;
  code nested on a line already counted isn't counted again; `coverage.lcov` is this run's,
  each test file of a workspace adding its own; and `--coverage` on a chip is an error, since
  the chip has no file to write the counts to. The counts are written once, whichever of a
  panic, `Environment.exit` and the end of `main` comes first, on whichever thread
  (`tests/ztest/coverage.sh`).
- `zs bench file.zs [filters] [--runs n]` (track D, item 9): `bench "name" (fun () -> …)` is a
  `Test` value among a file's `[<Tests>]`, timed in a process of its own after three warm-up
  runs: the median of 30 runs (or `--runs`) and its 95% confidence interval from the order
  statistics. The results are saved beside the file (`.zs-cache/bench/<file>.tsv`), and a
  benchmark whose interval doesn't overlap the saved one's, its median 10% or more away, is
  reported slower or faster; `zs test` runs a benchmark once, as a test of its body.
  `testFaster "name" fast slow` is a test that passes when `fast` wins 19 of 25 paired rounds (a
  sign test at 1%), so a performance claim can't silently regress (`tests/ztest/bench.sh`).
- `zs fuzz file.zs path [--for n] [-- flags]` (track D, item 6) runs one property under
  libFuzzer (the tests built with its instrumentation and the sanitizers; a panic aborts, so
  it's a crash), each input the property's bytes (`Gen.bytes ()` takes an input whole, so a
  property over bytes fuzzes a parser as it is), the corpus kept beside the file in
  `.zs-cache/fuzz/<file>/`, keyed by the property's path, so a run resumes (for `--for`'s
  seconds, or as long as libFuzzer's own flags say), the flags after `--` libFuzzer's but for
  those that start other processes (`-jobs`, `-fork`: it runs in one), its output read apart from
  the property's so neither stream blocks the other; a crash is shrunk by replays, shown, and
  saved as the failure `zs test` replays first (`tests/fuzz/fuzz.sh`).
- `zs test file.zs --target cortex-m4` (track D, item 11): the file's `[<Tests>]` built into one
  image and run under the chip's QEMU board (or a real board through probe-rs, as `zs run` does),
  every test in one process in order: Core's `Testing.runAll` prints `test path` before each,
  `ok path` after it and `skip path` for a pending one, and a failing test's panic ends the run,
  `zs test` naming it with what it printed, every line of the panic kept (blank ones, a
  property's case and replay seed); the counts as on the host. A property runs its cases there
  too, nothing recorded or shrunk, and a test returning a task runs on the chip's event loop
  (`tests/mcu/ztest.zs`, `tests/mcu/ztest_fail.zs`, both chips; neither has a task's test yet,
  so that one was checked by hand on both).
- `zs mcp` has `definition` (where the name at a position is defined: `file:line:column` and the
  defining line, in the program's files or the library's) and `explain` (its type with
  constraints, its effects in words, where it's defined, and its doc comment, a built-in's
  included) beside `check`, `type_at`, `docs`, `build`, `run`, `emit_llvm` and `format` (track E,
  item 3; `tests/mcp/session.sh`).
- `zs test --stress 10m` (track D, item 4): the tests at random on every core, over and over for
  that long (`30s`, `10m`, `1h`), each run its own process as always; a failure one run hides (a
  race, a leak on a rare path, a timeout under load) shows, each failing test shown once with its
  first failure. With `ZS_LEAKCHECK=1`, a leak at a test's exit (`leak check: n object(s) still
  allocated`) fails the test, in one run too; it was reported and the test passed
  (`tests/ztest/stress.sh`).
- `zs provide json <file>` and `zs provide csv <file>` print a module from a data source, to keep
  beside the program ([proposal 0001](docs/proposals/0001-type-providers.md), track P's first
  step): `json` gives a document's records with the `Json` derive and `parse` and `print`, an
  object a record named after its key (two with the same fields share one), an array a list,
  `null` or a key some objects lack an option, a number `int` when every occurrence is
  integral, a key that isn't a name a ``` ``backtick`` ``` field, with `--root=Weather` and
  `--types=temp:f64,readings.value:f32`; `csv` gives a `Row` record from the header and the rows
  (`int`, `f64`, `bool`, else `string`; an empty cell makes a column an option) with `parse` and
  `print` that read and write quoted cells, with `--separator=;`, `--hasHeaders=false` and
  `--types=volume:f64`. `zs provide sql`, `svd` and `c` print the other providers' modules the
  same way, and `zs provide <name>` a provider of your own on PATH; `zs provide --list` names the
  five and those on PATH (`tests/providers/provide.sh`).
- The tree-sitter grammar, and so Zed, parses the providers' imports (named, bare, with
  options), list and array ranges and typed tuple parameters; the Zed extension pins the
  grammar's commit with them.

### Performance
- `x <- f … x …` hands the call x's own reference when the other arguments only read x, so
  `counts <- HashMap.add w (Option.defaultValue 0 (HashMap.tryFind w counts) + 1) counts`
  updates the map in place instead of copying it on every update (a word count of 1M words: 84 s,
  now 0.23 s); the same for arrays (`a <- Array.set a i (a.[i] + 1)`). An argument that assigns
  x, or writes its array in place, keeps the copy (`tests/cow_args.zs`, `tests/cow_split.zs`).
- Only a program that can put a SIMD vector in a heap object has its objects 64-byte aligned by
  the system allocator; one with vectors in locals only keeps the pool. Calling
  `Bytes.appendJsonString` no longer costs a whole program the pool (a JSON round trip of 200k
  records: 3.5 s and 935 MB, now 1.4 s and 368 MB; `tests/simd/pool.zs`,
  `tests/simd/pool_locals.zs`, `tests/simd/pool_wide.zs`, `tests/simd/pool_wide_indirect.zs`).

### Examples
- `examples/aoc`: ten Advent of Code puzzles (2015 to 2021's first days), each solved on the
  puzzle's example input with only the prelude, Core and Std, 203 lines in all: track S's exit
  test that the library is enough for a day's puzzle (`tests/examples_aoc.sh` checks the
  answers).
- `examples/tools`: grep (38 lines), a JSON pretty-printer (16) and `tail -f` (49), each with the
  prelude, Core and Std alone (track S's exit test), built and run by `tests/examples_tools.sh`.

### Benchmarks
- `bench/host` has five small real programs beside its kernels, in Z#, C and Rust: `wordfreq`,
  `json`, `interp`, `pathfind` and `sha256` ([the report](docs/reports/realworld.md)).

### Tests
- CI's macOS runners get coreutils' `timeout`, which `./test.sh` and its scripts call and macOS
  doesn't have: most of each Mac's 130 or so failures on 2026-11-04, every guide example among
  them, were its absence. `test.sh` builds `tests/placement.zs` for macOS and Windows from any
  host and checks no section name is left, and expects the ELF names in a native build on Linux
  alone. `tests/debug/kinds.zs`'s DWARF check fails if `llvm-dwarfdump` crashes.
- The scripts run with BSD's tools, as macOS has them (a `wc -l` count's padding, `sed -i`, `stat
  -c` and `\|` in a `sed` pattern were GNU's), and two resolve their temporary directory as the
  compiler names it (macOS's `/var` is `/private/var`). A check that needs QEMU, Node or valgrind
  skips without it, as the others did; `tests/simd/arm.zs` runs natively on aarch64 Linux;
  `bench/host`'s baseline counts x86-64 Linux's instructions and is checked only there;
  `tests/debug/gdb.sh` and `lldb.sh` compare a frame's locals in name order, which debuggers list
  differently by machine.
- CI: the Intel Mac gets LLVM 23 from conda-forge (Homebrew's newest for Intel is 22, and LLVM's
  releases have no build for it), both Macs `SDKROOT`, so clang and libclang find the SDK's
  headers, and each native runner builds and runs one program first, each step bounded, and
  stops after three hours, so a hang shows where it is.
- `tests/lsp/providers.sh` edits its sample only once the server has answered the requests before
  it (a pipe the script writes as the server answers), so what the first hover and completion
  see no longer depends on who was faster; it failed one run in four under load.
- `./test.sh --sanitize` builds every program with the address and undefined-behaviour sanitizers
  (`zs build --sanitize`) and runs it, a report failing the test as valgrind's does, beside
  `--valgrind` and `--release`. A `.plain-only` file beside a test gives the reason it runs only as
  built (it measures the pool, or the runtime's stack guard), skipped under both.
- `./test.sh --release` builds every program optimized (`zs build --release`), so what LLVM may
  assume of the IR the compiler writes (no overflow where it says `nsw`, no aliasing where it says
  `noalias`) is tested too: each program must print the same.
- `tests/stress.sh`: long literals, long runs of statements and lets, deep nesting and a byte
  order mark build in time and run; a statement failing after a long literal is one error, the
  next statements checked; deeper than any stack is the panic above, not a crash.
- `tests/fuzz.sh`: 300 programs broken at random (seeded: `ZS_FUZZ_SEED` picks them, 1 unless
  it says, `ZS_FUZZ_COUNT` how many) through `zs check` and `zs fmt --stdin`: errors, never a
  crash, a panic or a hang.

## 0.6.2 (2026-10-30)

The first public release, for microcontrollers: firmware for a real board, the ST Nucleo-F401RE,
written as tasks on the runtime's loop, with interrupt handlers, registers as `[<Bits>]` records,
code checked not to touch the heap, and its log over RTT (`examples/nucleo`). Beside it: package
versions and the orphan rule for impls, Concurrent ML's events for tasks, lldb, doc tests,
`zs doctor`, allocation hints in the editor, and the guide's page for F# programmers.

Archives for Linux, macOS and Windows on x86-64 and arm64, each cross-built from Linux x86-64.
Linux x86-64's suite passes natively, Linux arm64's under QEMU (its compiler builds itself to
the same bytes), Windows x64's under Wine; the macOS builds and arm64 Windows are untested on
a real machine. The flagship runs under QEMU's STM32F405, not yet on the board itself.

### Language
- What an F# programmer writes in the first hour parses: `let y = x + 1 in y * 2`; a condition
  continued on a line starting with `||` or `&&` (and `|||`, `&&&`, `^^^`); a record on the line
  after its constructor (`Some` then `{ x = 1 }` indented); `match a, b with` without
  parentheses. `handle` is a keyword only where a handler starts, so `let handle x = …` is a
  function. `[<CLayout>]` and the other attributes apply to a `private` type.
- `[<Unsafe>]` on a function: only `unsafe` code may call it (`Bytes.writer`, which writes
  wherever its pointer points, is one).
- A top-level `Buffer` of one type (`let private seen: Buffer<int> = Buffer.empty`, or a record
  holding one) is one Buffer, computed once at startup, so a push to it is seen at every use; it
  was a new Buffer at each use, and the push was lost. A generic one, `Buffer.empty` itself, is
  still a new Buffer at each use.
- The orphan rule (K9): an impl written lives in its trait's package or its type's, so two
  packages can't both write one that a program using both would have twice. **To rewrite:** an
  impl of the library's trait for the library's type, or for a dependency's: wrap the type in a
  one-case union of your own. A hand-written impl used before it's checked (further on, or in a
  later module) is an error saying to write it before its first use; it was a wrong
  "does not implement" or "already implemented".
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
- The flagship, `examples/nucleo`: firmware for the Nucleo-F401RE as a project (`zs build` there
  builds it for the board, `zs test` tests its shell on the computer), three tasks on the
  runtime's loop: the LED's, the button's (`Irq.wait`) and a serial shell fed by USART2's
  handler through an `Spsc` and a `Signal`, its registers `[<Bits>]` records, its log over RTT.
  `./test.sh` runs it on QEMU's STM32F405, typing at its USART2.
- Tasks on a microcontroller (0016): the same `task { }`, `Task.run`, `sleep`, `both`, `all`,
  `race`, `timeout` and `scope` as on a computer, on the embedded runtime's event loop: timers on
  SysTick, the core asleep (`wfi`) when nothing runs. `Irq.wait n` is a task that goes on once
  line `n` fires; `Signal.set` from a program's own handler wakes the task in `Signal.wait`.
  `Runtime.setClock hz` after changing the core's clock. `Task` moved from Std to Core (the same
  namespace, so nothing changes on a computer); on a chip, reaching `Task.spawn`,
  `Task.blocking` or `Task.waitFor` is a compile error naming the chain. `examples/mcu/uart.zs`
  receives a line in a task waiting for the UART's interrupt. `Task.fromCallback` makes a task
  of a callback, for a driver's own waits.
- A real board, the ST Nucleo-F401RE (`--target nucleo-f401`, 0027): linked for its STM32F401RE
  (512 KB of flash at `0x08000000`, 96 KB of RAM), with its interrupt lines by name
  (`[<Interrupt "USART2">]`), and output over RTT, a ring in RAM the debug probe reads while the
  chip runs. `zs run --target nucleo-f401` flashes it with probe-rs, which shows the output and
  returns the exit status. With no probe attached, nothing waits: output that doesn't fit is
  dropped, and an exit leaves the core asleep (semihosting's breakpoint would fault there).
  Targets are found by name, so a board shares its core's triple: `[target.nucleo-f401]` and
  `[c.nucleo-f401]` are its own.
- A chip's image keeps its symbol table (`zig cc` dropped it at `-Os`) and its entry point (it
  was 0, where a debugger's `load` jumps).
- 32-bit Arm Linux (`--target arm-linux-musleabihf`) builds with 32-bit words, as its runtime
  has: it built with 64-bit ones, linking against a runtime that read them as 32.
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
- `[<Bits>]` records (0013): a record that is one unsigned integer, its fields ranges of its
  bits (`bool`, enums, `u8` to `u64`, `[<Width n>]` and `[<Bit n>]`, the first field
  attributes): `{ ue = true; te = true }` is one constant, a read a shift and a mask,
  `{ r with f = v }` a masked write keeping the gaps; compared as the integer, printed as the
  record. `Bits.toU32`, `ofU32` and the other widths, `raw` and `ofRaw`.
- `[<NoAlloc>]` and `--no-heap` (0012): a function that, or anything it calls, may allocate or
  free is an error naming the chain (`reply is [<NoAlloc>], but reply -> describe builds a
  string`); interrupt handlers and `Cpu.critical`'s bodies are checked the same way.
  `--no-heap` checks the whole program, startup values included, and builds a chip's image with
  no heap.
- A string built with `+` (an interpolation is one) is one allocation: its pieces are joined at
  once, where each `+` made a string of its own (`$"{name}: {qty}\n"` made five, and makes one
  beside `qty`'s text). An empty literal piece is left out, and a piece alone is the string
  itself, so `$"{s}"` allocates nothing and passes `[<NoAlloc>]`.
- `[<NoAlloc>]` passes code that frees nothing: dropping a value matched to a case without
  fields (a static cell), an option's `Some s` keeping its string, and `string` of a string (its
  own text). Its errors name an operator as written (`Ledger.<+`, which showed as `Ledger.`) and
  a dropped local without the compiler's numbering (`'o'`, not `'o.8'`).
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

### Security
- An allocation whose size overflows the word panics `out of memory`; wrapped, it was a small
  object that writes then ran past: `Array.create` and `Buffer.create` of more than the address
  space (2^61 ints made a 16-byte array its fill wrote past), `Channel.make`'s and
  `Spsc.create`'s slots, and on a 32-bit target a string's length (`String.replace` of 65,536
  `a`s by 65,537 bytes made a 64 KB string and wrote 4 GB into it). `String.sub`'s range check on
  a 32-bit chip no longer overflows either.
- Loop versioning evaluates a `for` loop's bounds once. Its range test and the loop each
  evaluated them, so a bound with an effect ran twice, and the copy without bounds checks could
  run over values the test never saw, reading outside the array.
- A float converted to an integer saturates, NaN to 0, as `F32x8.convert`'s lanes do
  (`u8 300.0` is 255): out of range it was LLVM's poison, x86's answer on one machine and Arm's
  on another.
- A NUL byte in a path, an environment variable's name, a host or a socket's path fails with
  `Invalid argument`: the OS read the name only up to it, so `"secret\0.txt"` opened `secret`, and
  a leading NUL made a Linux abstract socket, which any user can reach. `Process.run` and
  `Process.start` refuse an argument, program, directory or environment holding one (`"a\0b"`
  reached the program as two arguments), and pass an empty argument, alone or last (`start`
  dropped a last one, both a lone one).
- UTF-8: `String.ofBytes` and `for c in s` (`String.decodeAt`) take only RFC 3629's sequences, as
  `Utf8.validate` does: an overlong form, a surrogate or a value past U+10FFFF is U+FFFD.
  `C0 AE C0 AF` decoded as `./`, past a check of the bytes for `../`.
- A string's hash is SipHash-1-3 under a key drawn per process, as Rust's `HashMap` hashes:
  FNV-1a's was the same in every run, so whoever picked a `HashMap`'s keys (a JSON object's, from
  a socket) could make them all collide and every lookup walk them. A string hashes differently
  in each run; ints still hash to themselves.
- Numbers as text keep their `.` whatever locale a C library sets (`setlocale`: GTK's, an
  ncurses program's), on Linux and macOS: in de_DE's, `1.5` printed `1,5` and `Float.parse "1.5"`
  failed, so `Json.parse` read no fractions. `String.isFloat` and `String.toFloat` read as
  `Float.parse` does, without leading spaces or hex.
- Tools: the build server's directory is private (0700; under a umask of 0, any user could reach
  its socket and run `zs` commands as you), and two servers no longer share their request files.
  The MCP `docs` tool and `zs test --doc` on a library file write their scratch program in your
  cache, not under a fixed name in the shared temporary directory, where another user's link
  there was followed, and a `.zs-doctest.zs` they put there first could change between its
  writing and its build, which runs it. A build no longer leaves an empty file there for each
  object it compiles.

### Library
- `Threading.Alt`: Concurrent ML's events for tasks, on one event loop, as F#'s Hopac has them.
  `Alt.choose` commits exactly one branch and takes the others back, `withNack` tells the
  branches that lost, `guard` builds an event at each sync, and `Ch` and `Mailbox` are its
  channels. A cancelled sync leaves no waiter behind; deep chains of syncs and maps don't grow the
  stack. The guide's tasks chapter says when to choose events over plain tasks.
- The thread pool wakes a sleeping worker when work arrives: a worker woke every millisecond to
  look for work it could have missed (`tests/parallel/wake.zs`).
- `Bytes`: `readU16BE`, `readI32LE`, `writeU64BE` and the rest, integers at an offset in either
  byte order. `Text.Hex` and `Text.Base64` (with the URL-safe, unpadded `encodeUrl`/`decodeUrl`
  JWTs use), `Sha256.hash` and `Hmac.sha256`, in Core, so on chips and WebAssembly too.
  `Span.indexOf`, `startsWith`, and on bytes `equalsIgnoreCase`, `trim` and `parseInt`, so an
  HTTP or JSON scanner is ordinary code over spans (track S, items 12 and 13).
- Byte strings: `b"Content-Length: "` is a `span<u8>` of the literal's constant, nothing copied
  at startup. `Ptr.readUnaligned` and `writeUnaligned` (at any address: a `u64` or a SIMD
  vector in one load) and `Ptr.diff` (C's `end - start`).
- A byte writer in `Bytes`: `append`, `appendUtf8`, `appendInt` and `appendJsonString` (scanned
  16 bytes at a time) add to a `Bytes.Writer` and return it, so a response is a pipeline:
  `w |> Bytes.append b"Content-Length: " |> Bytes.appendInt n`. A Writer pushes onto a Buffer
  (`Bytes.writerOf`) or fills fixed C memory such as a send buffer (`Bytes.writer p n`, unsafe;
  writing past its end panics); `Bytes.written` is what it wrote, as a span.
- `Bytes.readF64BE`, `writeF32LE` and the rest of the floats, and `Float.toBits32`/`ofBits32`
  beside `toBits`/`ofBits`.
- `List.collect` and `List.concat` are linear: they copied what they'd gathered for every list,
  quadratic in how many there were. `Set.union` adds the smaller set to the larger one,
  `intersect` walks the smaller one, both build their result from its sorted elements in linear
  time, and `difference` gives back `a` itself when `b` takes nothing from it.
- `List.maxBy` and `minBy`; `Array.max`, `min`, `maxBy`, `minBy` and `sumBy`.
- `unit` has `Show`, printing `()` as F# does, so `result<unit, int>` and the like print.
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
- `Map.add` and `Map.remove` (so `Set.add` and `Set.remove`) build the new node in the cell of the
  one they took apart when the map is unique and the node is still balanced, as it almost always
  is: adding to a map nothing else holds allocates one node, not one for each level. A million
  adds and lookups take 136 ms where they took 289.
- The runtime's string search (`String.indexOf`, and through it `contains`, `split`, `replace` and
  `lastIndexOf`) goes from one place the first byte is to the next with `memchr`, comparing the
  rest only there: it called `memcmp` at every byte. logstat reads 2 million lines on one core in
  1.21 s where it took 1.78.
- An integer's text is made without `snprintf`, and `println` writes a line under 256 bytes with
  its newline in one write, so another thread's output can't land between them: printing 5
  million lines of two numbers takes 0.46 s where it took 0.79.

### Packages
- Versions (0018 item 2): `json = { git = "…", version = "1.2" }` takes the repository's releases
  (tags `v1.2.3`, 1.2.0 or later below 2.0.0) by minimal version selection, as Go's: each
  package gets the highest version asked for it, so a diamond builds the same on every machine
  with no solver. `zs.lock` records the release; `zs update` raises the project's own versions
  to the newest. A major of 2 or more is another package with its own key (`json2`), so both build
  in one program.

### Tools and docs
- Allocation hints in the editor (0011, 0026): with `allocationHints: true` in the language
  server's initialization options (`zsharp.allocationHints` in VS Code,
  `lsp.zs.initialization_options` in Zed), each line shows what it does to the heap, from the
  compiler's passes after checking: `allocates ×2`, `reuses t`, `copies on write`, the objects
  and their sizes in the tooltip (`builds a cell of Tree (Node, 32 B)`). A line counts the one
  path through it that allocates most, so a match's arms (and a decision tree's copies of one)
  aren't added up. Hover on a function adds what its own code allocates and whether
  `[<NoAlloc>]` would pass, or the chain to what doesn't. A module of a project (a `zs.toml`
  above it naming another main file) has the hints the project's program gives its code.
- The compiler is faster, found with its own allocation hints and a profiler: building itself from
  an empty cache takes 16.8 s where it took 23.8 s, its own passes 3.7 s where they took 8.1 s,
  with 217 million allocations instead of 626 million and a peak of 744 MB instead of 859. A node's children are listed without copying the node, the names
  an expression binds and uses are gathered in one walk, a type a substitution leaves as it is
  isn't copied, code generation keeps each type's LLVM type and each union's cases, borrowed
  parameters are worked out again only for the functions whose callees changed, and reference
  counting no longer makes a closure of its whole state at every node. A change to the inliner
  or closure conversion rebuilds in 0.65 s where it took 4.7 s: their functions that take
  functions say those are pure, so a caller with effects no longer compiles its own copy of them.
- A program with threads has less code: a type's share and move walks are one function (the mode
  an argument), and a closure's walk and drop are one function for each list of captured types,
  not one for each closure. The compiler's binary is 9% smaller, its IR 8%.
- A program with threads allocates faster on macOS: what the allocator keeps for a thread (its
  counts, the pool's free lists and chunk) is one thread-local, found once per allocation; each
  was its own, and macOS finds a thread-local by a call (the compiler spent 4% of its time there).
- Loop versioning proves more of a `for` loop once, before it runs: its writes (`a.[i] <- v`) as
  well as its reads, indexes without the loop's variable (`x.[i]` in a loop over `j`) or any whose
  range follows from the loop's (`r * w + c`, `(j + 3) % 5`), and its `+ - *` over the variable and
  what the loop doesn't change, which then run without overflow checks. Each such expression's
  range is computed before the loop; if computing it overflows, the checked copy runs
  (`tests/versioned_loops.zs`). nbody takes 0.80 s where it took 0.91 (C's 0.76), spectralnorm
  0.42 s where it took 0.48 (C's 0.68).
- A build whose checked modules came from the cache, made by a build that named a file another
  way (`tests/x.zs`, then its full path), gives a pass's error its file and line: it printed
  `: error:` with neither.
- The guide's "Z# for F# programmers" page (`docs/guide/17-from-fsharp.md`), and posts on the
  strongest results (`docs/posts`: Perceus on a Cortex-M, atomic counts only where threads meet,
  SIMD next to C).
- `zs doctor`: what builds need, found here or not, with how to get what's missing (clang,
  zig, libclang, git, QEMU, probe-rs, Node, lldb or gdb). `zs` alone lists the commands.
- Doc tests: a fenced `zsharp` block in a `///` comment is an example that `zs test --doc` builds
  and runs, its `// => text` lines checked against what it prints, and `zs test --doc --update`
  rewrites them. The library's first examples (`List.groupBy`, `chunkBySize`, `maxBy`,
  `Array.maxBy`, `Map.change`, `Utf8.validate`, `Math.clamp`) run in `./test.sh`.
- lldb, the debugger on macOS, works on `zs build -g` programs as gdb does: breakpoints on Z#
  functions and lines, stepping, backtraces with Z# files and lines, and strings, records and
  unions as values (`tests/debug/lldb.sh`). It names the types as C's: a 64-bit `int` is a `long`.
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
