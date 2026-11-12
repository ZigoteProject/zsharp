# Packages

What a package is, how to make one, how to wrap a C library, and the rules for the package
manager's own code. For users, [the guide](../guide/08-programs.md#projects) has every command
and key; [proposal 0018](../proposals/0018-packages.md) is the design and its reasons.

## The model

- **A package is a folder with a `zs.toml`,** its modules in Z#, and the C it wraps.
- **Dependencies are source:** a path, or a git repository checked out into `.zs-cache/deps/`
  and pinned by `zs.lock` (the commit and a hash of the files). There is no registry.
- **A dependency's modules sit under its name.** `json`'s main file is the module `Json`, its
  `Parser.zs` is `Json.Parser`. Two packages may each have a `Util`.
- **Versions are git tags** `v1.2.3`. `version = "1.2"` means 1.2.0 or later, below 2.0.0. A
  build takes the highest minimum anyone asks for: no solver, the same answer on every machine.
  Major version 2 is another package with its own key.
- **`internal/`** at any depth hides modules from other packages.
- **The orphan rule:** an impl is written in its trait's package or its type's.

## A manifest

```toml
[package]
name = "wc"
version = "0.1.0"
main = "src/main.zs"        # the default

[dependencies]
text = { path = "../text" }
json = { git = "https://github.com/someone/json", version = "1.2" }

[c]                         # the C this package wraps
sources = ["c/shim.c"]      # compiled and linked with the program
include = ["c"]             # where `import c` and the sources find headers
link = ["m"]
pkg-config = ["sqlite3"]    # host builds only

[c.cortex-m4]               # added to [c] for one target
link = ["…/libkit.a"]

[provider]                  # the package is a type provider
main = "Provider.zs"
```

`[workspace] members = [...]` in a root `zs.toml` gives several projects one `zs.lock`, one
`.zs-cache/` and one `vendor/`.

| Command | Does |
|---|---|
| `zs new <name>` | creates a project: `zs.toml`, `src/main.zs` with a test, `.gitignore` |
| `zs add <path>` / `zs add <git url>@1.2` | writes the dependency and fetches it |
| `zs remove <name>`, `zs tree`, `zs fetch`, `zs update` | as named |
| `zs vendor` | copies git dependencies into `vendor/`; with `--offline` a build needs no network |

Commit `zs.lock`. Never edit a checkout under `.zs-cache/deps/`: it's restored from its commit.
To change a dependency's code, make it a path dependency.

## Wrapping a C library

Bind the existing, proven library; don't rewrite it in Z#. The two packages here are the
pattern:

```
packages/xxhash/
  zs.toml            # [package] name, main; [c] sources
  src/Xxhash.zs      # the Z# API: safe functions over the externs
  c/xxhash.c, .h     # the library's source, unmodified
  c/LICENSE          # its license, kept beside it
```

1. **Vendor the source, or link the system's.** Small, stable, single-file libraries are copied
   into `c/` unmodified, with their license and the version in `zs.toml`'s header comment
   (`xxhash`). Large ones are found on the system and opened or linked (`libclang`, through a
   small `c/shim.c`).
2. **Declare it** with `import c "header.h"` or `extern`, in the package's `[c]`, so a user's
   project needs nothing but the dependency.
3. **Offer a safe API.** The module's public functions take and return Z# values, check lengths
   and results, and keep `unsafe` inside. A user of the package never writes `unsafe`.
4. **Own the resources.** A handle from C is released by a `use` value or a finalizer, not by
   the caller remembering to.
5. **Say which targets work.** A package that needs an operating system can't be a chip build's
   dependency; the build says so by name.
6. **Add the license** to the README's License section when the code ships in the repository.
7. **Test it** as the suite tests packages: a project under `tests/project/` and a script with
   its `.expected` (`tests/project/cwords` wraps C).

A Rust crate or Zig package built as a static library with a C header is C to Z#
(`examples/rust`, `examples/zig`).

## In this repository

| Package | Is | Used by |
|---|---|---|
| `packages/xxhash` | xxHash 0.8.3's XXH3, vendored | the compiler's cache keys and lock hashes |
| `packages/libclang` | the system's libclang, opened when first used | `import c` |
| `packages/sqlite` | SQLite 3.54.1's amalgamation, vendored and built through `c/shim.c` ([0032](../proposals/0032-first-party-packages.md)) | programs, as a path dependency; `tests/packages/sqlite.sh` |
| `packages/tls` | Mbed TLS 3.6.7's `library/` and `include/`, vendored, under `c/shim.c` | programs and `packages/http`; `tests/packages/tls.sh` |
| `packages/http` | llhttp 9.4.3's generated parser, vendored, under `c/shim.c`; depends on `packages/tls` | programs, `examples/service`; `tests/packages/http.sh` |

Each of the three keeps its library's release, the archive's hash and where it came from in
`c/VERSION`, and a hash of every vendored file in `c/SHA256SUMS`, which its test checks: a
vendored file is never edited. An option a library takes as a `#define` is set in the shim that
includes it (`sqlite`) or in a header placed before the library's own on the include path
(`tls`'s `c/config`), since `[c]` has no key for one.

`src/zs.toml` names the first two as path dependencies. They're compiled by stage 0 as part of the
compiler, so their Z# follows [the compiler's rules](code-style.md#the-compiler-src).

## Changing the package manager

It reads manifests, lock files and repositories someone else wrote, so its input is hostile
([security](security.md#packages-and-the-build)):

- A name, a `main`, a path in a manifest or a lock entry is validated before it becomes part of
  a path. Nothing leaves the package's directory.
- A symbolic link in a dependency is hashed as a link and never followed; a pipe or a device is
  an error.
- zs writes nothing into a dependency's directory. What it keeps for one is in the project's
  `.zs-cache/pkgs/<name>-<hash>/`, and it refuses to write through a symbolic link.
- Resolution needs no network once `zs.lock` and the checkouts exist, and gives the same result
  on every machine.
- Every behavior has a script in `tests/project/` (`git.sh`, `pkgs.sh`, `vendor.sh`,
  `workspace.sh`, `links.sh`, `depcache.sh`). A change adds to one.

**Not built yet:** `zs add` by name and the index it needs (a draft in 0018), and a second major
version in a `v2/` directory.
