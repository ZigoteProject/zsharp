# Development

Setting up, building the compiler, running and adding tests, and finding out why something
fails.

## The container

Development happens in a podman container (`.devcontainer/Containerfile`: Fedora, LLVM 23 from
LLVM's own release, zig, valgrind, gdb, QEMU, Wine, Node). `./dev <command>` runs a command in
it and builds the image the first time.

```sh
./dev ./test.sh                  # build the compiler, run every check
./dev bin/zs run hello.zs        # the compiler the suite built
./dev                            # a shell
./dev --rebuild <command>        # rebuild the image first
```

- **One at a time.** Every run shares `bin/` and `build/`; two suites at once break each other.
- **`:z`, not `:Z`.** `./dev` mounts the repository with a shared SELinux label. Another tool
  mounting it with a private one cuts a running container off from its files.
- **Without the container:** clang 23 or later and a released `zs`
  ([the guide](../guide/01-getting-started.md) has the commands). CI's macOS and Windows jobs
  work this way. The container is what the suite is known to pass in.

## Stage 0

The compiler is written in Z#, so building it needs a compiler. That one is **stage 0**: a
release pinned in `dev` by version and SHA-256 (0.7.1 today), taken from `dist/` or downloaded
from the repository's releases, and unpacked into `build/stage0/`. Inside the container it's
`$ZS_STAGE0`.

- **`src/` is written in stage 0's Z#.** A language feature or library function newer than that
  release can't be used in the compiler until stage 0 moves ([how](release.md#moving-stage-0)).
  `lib/`, `tests/`, `examples/` and `packages/` used by programs are compiled by the new
  compiler and may use everything.
- **Don't delete `build/stage0/` or `dist/*.tar.gz`.** They may be the only copies on the
  machine, and a private repository's releases can't be fetched without credentials.

## Building the compiler alone

`test.sh` does this first; to do only this:

```sh
./dev bash -c 'ZS_RUNTIME=$PWD/runtime ZS_NO_SERVER=1 "$ZS_STAGE0" build src/Main.zs --release -o build/zs \
  && src/install.sh build/zs bin'
```

`src/install.sh` puts `zs` in `bin/` with a **copy** of `lib/` and `runtime/` beside it, which is
where `bin/zs` reads them from. After editing the library or the runtime, run `install.sh`
again, or the edit isn't seen.

## The test suite

`./test.sh` builds the compiler, installs it into `bin/`, and runs every check. It prints
`ok`, `skip` or `FAIL` per check and exits non-zero on any failure. Its last lines are the count
of failures and each `FAIL` line again, or `all passed`: read a long log from its end.

| Mode | Adds |
|---|---|
| `./test.sh` | the whole suite, programs built `--strict` |
| `--valgrind` | each program under valgrind: a memory error or a leak fails it |
| `--sanitize` | programs built with the address and undefined-behavior sanitizers |
| `--release` | programs built optimized, which must print the same |
| `--target <triple>` | cross-compiled and run under qemu-user or Wine (`aarch64-linux-musl`, `x86_64-windows-gnu`) |
| `--zs <binary>` | test that compiler instead of building `src/` (what CI's native jobs do) |
| `--only <text>` | the programs in `tests/` whose path has the text, and none of the tool checks |

How tests are written, the file conventions and which tests a change needs:
[testing](testing.md).

## While iterating

The suite is long. Rebuild the compiler, run the one test, and run everything once at the end.
Put a timeout on anything that could hang (`timeout 60 bin/zs …`), as CI does.

```sh
./dev ./test.sh --only tests/newcomer/          # rebuild the compiler, run those programs
./dev ./test.sh --zs build/zs --only open_own   # the compiler as last built, one program
diff <(./dev tests/cache.sh 2>&1) tests/cache.expected   # a script's check, by hand
```

## An agent's tools

`.mcp.json` at the root gives an MCP client that reads it (Claude Code does) the compiler's own
server, `./dev -i bin/zs mcp`: `check`, `type_at`, `explain`, `docs`, `guide`, `run` and `test`
on the checkout's files, from the compiler the suite last built (so run the suite once first).
It is started without `--trust`. It runs beside a suite, reading `bin/`: while `src/install.sh`
replaces `bin/lib` a call can fail, and is asked again.

## Finding out why

| Setting | Does |
|---|---|
| `ZS_NO_SERVER=1` | each build in its own process, not through the build server |
| `ZS_CHECK_IR=1` (`zs build --check-ir`) | the compiler checks its IR after each pass |
| `ZS_DUMP_IR=<dir>` | keeps each module's LLVM IR |
| `ZS_DUMP_CORE` with `--emit-llvm` | prints the compiler's Core IR (the whole-program path only) |
| `ZS_LEAKCHECK=1` | a program reports objects it leaked, at exit |
| `ZS_BACKTRACE=0` | a panic prints no backtrace (deterministic output) |
| `ZS_NO_POOL=1` | objects from `malloc`, so valgrind and the sanitizers see each one |
| `ZS_LIB`, `ZS_RUNTIME` | the library and runtime directories to use instead of those beside `zs` |
| `ZS_OFFLINE=1` | a fetch is an error |

- `zs build -g`, then gdb or lldb; `--sanitize` and `--sanitize=thread` for memory and races.
- `zs doctor` lists the tools builds need and which are missing.
- **An import that works here and fails in CI:** saved `import c` results in `.zs-cache/` can
  hide a broken live import. Check import changes in a fresh clone.
- **A compiler panic** names the pass. It's always a bug: errors in a program are diagnostics,
  never a crash.

## Branches and pull requests

- `master` is the main branch and always passes the suite.
- Work on a branch, open a pull request into `master`, and merge it with a merge commit once
  CI's six jobs are green.
- A long-lived branch merges `master` in, with a message saying what came
  (`Merge master (Windows natively, share in record fields) into the review`).
- **After any merge, build and re-read every file both sides changed.** git has joined two
  edits into code that doesn't compile without reporting a conflict.
- A reformat-only commit goes into `.git-blame-ignore-revs`.

## Working beside others

More than one person or agent may be editing this checkout. Look at `git status` before
starting; leave files you didn't change alone, uncommitted changes included; commit and push
only when asked.
