# Security

What Z# promises, where untrusted input enters, and the rules that keep both true. The findings
these rules come from are in [the review of 0.7.0](../reports/security-review-0.7.md): 106
defects, most of them one of the patterns below.

## Two promises

**1. Safe code is memory-safe.** A program with no `unsafe` and no `extern` has no
use-after-free, no out-of-bounds access, no uninitialized read, no data race and no silent
integer overflow ([DESIGN §5.3](../../DESIGN.md#53-what-code-without-unsafe-guarantees)). If
safe Z# can break one of these, the compiler, the library or the runtime has a bug, and it's a
security bug whoever wrote the program.

**2. The tools survive hostile input.** Opening a project, fetching a package or parsing a file
doesn't run its code, write outside its directories, crash or hang.

## Trust boundaries

| Input | Trusted? |
|---|---|
| your own code, compiled with `zs build` | yes. It runs type providers, as `cargo` runs build scripts |
| a project opened in an editor (`zs lsp`) or by an agent (`zs mcp`) | **no.** Nothing of it is built and run without `--trust` |
| a fetched dependency: its manifest, files, links, lock entry | **no** |
| a request on the build server's socket | **no** |
| a type provider's input file and its output | **no.** What it writes into a module is quoted |
| what a Z# program reads at run time: files, sockets, JSON, arguments | **no.** The library must hold up |
| the stage 0 archive, toolchains CI downloads | only after a checksum |

A new feature that reads something states which row it's in before it's written.

## Rules by component

### The checker and the optimizer

- A safety rule (`Share`, `unsafe`, `[<NoAlloc>]`, a closure's captures, exhaustiveness) is
  checked on every path that can build the construct: generics, effects, tasks, derives.
- An optimization may remove a check only where it proves the check true. Bounds-check hoisting
  once took a Buffer's owner pointer for its length; the proof has to be about the right value.
- A literal, shift or conversion outside its type is an error or a panic, never truncation.
- Every such fix has a test that fails without it.

### The runtime (C)

- Lengths and indexes from Z# are checked in C too, wherever C is the last line.
- A size computed from input is checked for overflow before `malloc` or `memcpy`.
- A type that is `Share` is safe under any use safe code can make of it, not only the intended
  one (`Spsc` was Share and assumed one producer).
- A stack overflow, an exhausted heap or descriptor table is a panic or an `Error`, on a chip
  too. Nothing is overwritten.
- Changes run under `--sanitize`, `--sanitize=thread` and `--valgrind`.

### The library

- **Parsers bound their work:** depth (`Json.parse`, `Binary.ofBytes`), and a length never past
  the bytes actually there.
- **Secrets are compared in constant time:** `Hmac.verify`, `Bytes.fixedTimeEquals`.
- **Processes:** arguments are passed as an array, never through a shell. On Windows a `.bat` or
  `.cmd` goes through `cmd.exe`'s quoting, and what can't be quoted is an `Error`.
- **Files:** an operation on a symbolic link acts on the link (`Directory.deleteRecursive`
  removes it and never follows it). Replacing a file is a rename of a finished copy.
- **Networking:** a blocking lookup doesn't run on the event loop; a failing `accept` doesn't
  spin.
- **`unsafe`** is small and behind a function that validates. `[<Unsafe>]` marks a function that
  trusts its arguments.
- Don't write cryptography beyond what's there. Bind a reviewed library as a package.

### The servers: `zs lsp`, `zs mcp`, the build server

- They open whatever an editor or agent points them at. They build and run a project's code (a
  dependency's type provider) only with `--trust`; without it, the module from the last trusted
  build, or an error that says why.
- An extension passes `--trust` only for a workspace the editor itself marks trusted.
- A request's paths and URIs are decoded and validated before use; a malformed message is an
  error reply.
- A provider program is stopped after its timeout, and its input must be a regular file.

### Packages and the build

- Nothing in a manifest or lock entry reaches a path unvalidated; `main` stays inside its
  package; a `zs.toml` is at most 1 MB.
- Links are hashed as links, never followed, and vendored only when they stay inside the
  package.
- zs never writes into a dependency's directory or through a symbolic link.
- `zs.lock` pins a commit and a hash; a checkout that differs is restored or is an error.

### Scripts and CI

- **Pin and verify.** A downloaded archive is checked against a SHA-256 before anything of it is
  unpacked or run (`dev`, the Containerfile, the workflow). Actions are pinned by commit hash.
  Never pipe a download into a shell or into `sudo tar`.
- **Least privilege.** The workflow's token is `contents: read`; `persist-credentials: false` on
  checkout. A step that needs more says why.
- **No secrets** in the repository, in logs or in test fixtures.
- **A script deletes only what it can prove is its own,** and tests each step: a `&&` list gets
  past `set -e`.
- **Release archives** are owned by root with no group or world write (`tests/release.sh`).

## Reviewing a change

- [ ] Which trust-boundary row does its input fall in? Is everything from an untrusted row
      validated before use: lengths, depths, names, paths, links?
- [ ] Can safe code reach memory it doesn't own, or a race, through this?
- [ ] Is every new `unsafe` minimal, commented and behind a checking function?
- [ ] Does anything new run code, start a process or touch the network? Under whose trust?
- [ ] Does a failure give an `Error` or a diagnostic, not a crash, a hang or a partial write?
- [ ] Is every new download pinned and checksummed?
- [ ] Is there a test with the hostile input?

## Known gaps

Kept current in [the review](../reports/security-review-0.7.md#fixed-in-part-deferred): the
lock's hash is XXH3-128 until stage 0 has SHA-256; `[<NoAlloc>]` misses a few frees the code
generator expands; some of CI's downloads are pinned by version only. Also, by design:
reference cycles leak, and a panic ends the process.

## Reporting a vulnerability

Privately, as [SECURITY.md](../../SECURITY.md) says: never in a public issue. A fix lands with
its test and a line under *Security and stability* in `CHANGELOG.md`.
