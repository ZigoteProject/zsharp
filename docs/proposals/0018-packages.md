# Proposal 0018: packages

| | |
|---|---|
| **Status** | Approved in principle. Items 1 (namespaced dependencies, `tests/project/two`) and 4 (the `[c]` section, `tests/project/cwords`; `[target.<name>.c]` with 0022) are built; versions, internal modules, C dependencies, targets, integrity, commands and workspaces (items 2–8) after it. Draft for the index |
| **Decided at** | track K's plan ([ROADMAP](../../ROADMAP.md#packages-k)); phase 12's "before 0.1" list takes item 2 ([ROADMAP](../../ROADMAP.md#phase-12-release-01)); the index at a later design review |
| **Builds** | track K: packages |
| **Rests on** | decisions 26 (`zig cc`), 27 (source packages, `zs.lock`), 37 (Core and Std) in [DESIGN §13](../../DESIGN.md#13-decisions); [DESIGN §12](../../DESIGN.md#12-tooling) Projects |
| **Related** | [0001 type providers](0001-type-providers.md) (provider packages), [0020 the compiler in Z#](0020-self-hosting.md) (`libclang` and `xxhash`), [0022 macOS and Windows](0022-targets-macos-windows.md) (C flags per target), [0024 the library](0024-library-api.md) (what stays a package), [0014 placement](0014-placement.md) (`[target.<name>]`), [0007 incremental builds](0007-incremental-builds.md) (the cache a dependency's modules share) |

- [x] Approved in principle (items 1–8)
- [ ] Discussion (the index)
- [ ] Implementation

## Summary

A package is a folder with a `zs.toml`, its modules in Z#, and the C it wraps. Dependencies
are source (decision 27): a path or a git repository, checked out into `.zs-cache/deps/` and
pinned by `zs.lock`. This proposal takes track K whole. A dependency's modules sit under its
name (`Json.Parser`), so two packages with a `Util` module don't collide. A version picks
among a repository's `v1.x.y` tags, and a build takes the highest of the minimums asked for
each package, as Go does: no solver, the same answer on every machine, recorded in `zs.lock`
with a hash of each checkout. A package's `[c]` section compiles and links the C library it
wraps, so `zs add sqlite` is the whole setup. An `internal/` directory hides modules, a
microcontroller build rejects a package that needs Std by name, `zs vendor` and `--offline`
make a build need no network, and a workspace shares one lock. Later, an index as a git
repository gives names, so `json = "1.2"` works without anyone running a service.

```toml
[package]
name = "app"
version = "0.3.0"

[dependencies]
text = { path = "../text" }
json = { git = "https://github.com/someone/json", version = "1.2" }   # v1.2.0 or later, within major 1
sqlite = "0.4"                                                         # through the index, later
```

```fsharp
open Json                                  // the package's root module: its main file

let keys (doc: string) =
  Parser.parse doc |> Result.map Json.Util.keys   // Json.Parser and Json.Util: its other files
```

Item 2 and the index need a new decision row, numbered by the coordinator; decision 27 covers
the rest.

## Motivation

**Two packages, one `Util`.** Today a dependency's files are modules named after the files,
looked up in a flat list of directories where the first match wins (`moduleDirs` and `fileOf`
in `src/Driver.fs`, commit d6eb26d lines 140–166 and the main checkout's 583, approximate;
facts sheet §9). Two dependencies that each have a `Util.zs` build against the first one's,
silently, and a program's own `Util.zs` shadows both. The only fix changes what names mean,
so it comes before there are packages to break (the ordering rationale's last rule).

**A diamond.** `app` depends on `yaml`, which needs `json` 1.1 or later, and on `toml`, which
needs 1.3. Without versions, `rev = "v1.1"` in one manifest and `rev = "v1.3"` in the other is
an error today (two URLs or revs under one name, `fetchDeps`, d6eb26d line 291), and the only
way out is editing a dependency. Track K's exit test is that this resolves to 1.3 everywhere.

**A wrapper's flags.** A package that wraps SQLite writes `[<Link "sqlite3">]` on its
`import c "sqlite3.h"` ([DESIGN §11](../../DESIGN.md#11-c-interop)), and then every project
that uses it needs the header on the include path and the library where the linker looks,
found by hand. A C++ library has no header `import c` can read at all. With a `[c]` section
the package carries its sources, include paths and link line, and the exit test holds: a
project uses `zsharp/sqlite` after nothing more than `zs add`.

**A firmware project** adds a package whose helper opens `Console`. Today the error comes from
inside that module ("a name from it is a compile error that says why",
[DESIGN §9](../../DESIGN.md#9-compiler)), naming a file the project never opened. The right
error names the package, before any module is checked.

**Trust and the network.** A tag can move, a checkout under `.zs-cache/deps/` can be edited,
CI runs without a network, and a repository that must hold its own sources has no way to
today. A hash per checkout, `zs vendor` and `--offline` are the answers every package manager
converged on.

**What exists, and what carries over.** Go modules (2019) are the model: minimal version
selection, `internal/`, `/v2` for a new major, a directory hash per module, `vendor/`, and no
registry (the proxy is a cache, not a namespace). They were designed for a language with
source packages and no solver, which is Z#'s situation, and they are reproducible from
manifests alone. Cargo and NuGet contribute the commands (`zs add`, `zs tree`), the lock as a
file people commit, and the shape of a declarative C section in place of a build script.
F# programmers know NuGet's model; what changes for them is that a version is a minimum, not
a range, and that a build never moves on its own.

## Detailed design

### The manifest

`readManifest` reads a hand-written TOML subset: `[sections]`, `key = "string"`, inline tables
`{ k = "v" }`, `#` comments anywhere, an unknown section is an error (d6eb26d lines 66–121).
The subset grows by arrays of strings (`[ "a", "b" ]`), dotted section names, and a bare string
as a dependency's value. Every section:

| Section | Keys | Meaning |
|---|---|---|
| `[package]` | `name`, `version`, `main` | as today; `version` is the package's own, and a release is the tag `v<version>` |
| `[dependencies]` | `k = { path = … }`; `k = { git = …, version = … }`; `k = { git = …, rev = … }`; `k = "1.2"` (index) | item 2; `rev` keeps today's meaning, an exact pin on a tag, branch or commit |
| `[c]` | `sources`, `include`, `link`, `pkg-config` | item 4 |
| `[target.<name>]` | `heap`, `stack` | [0014](0014-placement.md); `<name>` is what `--target` takes (`cortex-m4`, `aarch64-macos`) |
| `[target.<name>.c]` | the `[c]` keys | added to `[c]` when building that target ([0022](0022-targets-macos-windows.md)) |
| `[workspace]` | `members` | item 8 |
| `[provider]` | *(unresolved)* | a package that is a type provider ([0001](0001-type-providers.md)) |

A section for a target that isn't being built is ignored, so one manifest serves every target.

### Namespaced dependencies (item 1)

- **The name:** a dependency's key, with its first letter upper-cased, is the module its code is seen under: `json` gives `Json`; a `-` is dropped and the next letter upper-cased (`tree-sitter` gives `TreeSitter`). A key is letters, digits, `-` and `_`.
- **The root** is the package's `main` file, whatever it's called: `main = "src/Json.zs"` or `src/lib.zs` is the module `Json`. A `module` header in it that says anything else is an error (*Unresolved questions*, 2).
- **The other files** under the main's directory are named by their path under the root: `src/Parser.zs` is `Json.Parser`, `src/Ast/Expr.zs` is `Json.Ast.Expr`. This is the rule the library already has: `core/Collections/List.zs` is `Collections.List` (`src/Driver.fs`, main checkout line 394).
- **Inside the package** nothing changes: its files say `Parser.parse` and `open Ast.Expr`, as today.
- **From outside:** `Json.Parser.parse`, or `open Json` and then `Parser.parse`. `Json.Parser` lexes as one qualified identifier (`src/Syntax.fs`, main checkout line 312) and `open` resolves it against the known modules (`src/Typer.fs`, main checkout line 3495), so there is no syntax change.
- **The program's own modules** stay unqualified (`Geometry`, as [the guide](../guide/08-programs.md) says): a program isn't a package to itself, and neither is a package to its own tests.
- **Transitive dependencies** are seen from the files of the package that lists them: `Json`'s `text` is `Text` inside `Json`'s files, and in the program's only if the program lists it too. A key names one package throughout a build; two manifests giving one key to two packages is an error, as today.
- **The key is the package's name:** the dependency's own `[package] name` must equal the key, with one exception in item 2 (a second major). So one package is one set of names in every file of a build, and its checked result (0007) serves every importer.
- **Core and symbols:** a dependency's declarations are qualified by the full module name (`Json.Util.keys`, the symbol `zs.Json.Util.keys`), so two `Util`s are two symbols, and the cache's keys change once, at the upgrade.
- **The library** is unchanged, and so is its precedence: a module named like a library namespace (`Text`) shadows it for qualified names, as today (decision 37).
- **In the driver:** `moduleDirs` becomes a map from a key to the package's main file and directory; `fileOf` looks a dotted name up by the longest prefix that is a key; `summaryOf` keeps the whole prefix of an `X.Y.z` token, not `X` alone (facts sheet §9).

### Versions and minimal version selection (item 2)

- **The form:** `json = { git = "https://…", version = "1.2" }`. A version picks among the repository's tags of the form `v<major>.<minor>.<patch>`. `"1.2"` means 1.2.0 or later, `"1.2.3"` means 1.2.3 or later, both below 2.0.0. `"0.4"` means 0.4.0 or later below 2.0.0: as in Go, 0.x and 1.x are one series, and 1.0.0 is a promise of stability, not a break. `rev` and `version` in one dependency is an error.
- **Identity:** a package is its URL and its major: `json` for majors 0 and 1, `json/v2` for 2, `json/v3` for 3. Two majors are two packages that may both be in one build.
- **Selection:** start from the program's manifest. Each dependency asks for a minimum. Each package gets the highest minimum asked for it; that version's manifest asks for its own; repeat until nothing rises. There is no solver and no "newest": a release changes nothing until a manifest asks for it, and the result follows from the manifests alone, so the diamond gives 1.3 on every machine, and a build a year later gives the same.
- **Tags** come from `git ls-remote --tags <url>`, with no clone, when a dependency is new or its line changed. The chosen tag is checked out into `.zs-cache/deps/<key>` as a `rev` is today (`fetchDeps`, d6eb26d lines 227–307). A build that finds every dependency in the lock runs git only for a missing checkout.
- **The lock** records the result: `json = { git = "…", version = "1.3.0", commit = "9fceb02…", hash = "sha256:…" }` (item 6 adds `hash`). It is a record, not an input: when it disagrees with the manifests, resolution runs again and rewrites it.
- **`zs update [key]`** raises the named dependencies' minimums in `zs.toml` to the newest tags within their majors, then resolves and writes the lock; with no key, all of them. A `rev` dependency keeps today's meaning: the newest commit of its branch.
- **A second major in one program:** two keys, one URL:

```toml
json  = { git = "https://github.com/someone/json", version = "1.4" }
json2 = { git = "https://github.com/someone/json", version = "2.1" }   # the package json/v2, the module Json2
```

  The key for a major of 2 or more may be the package's name followed by the major, which is the one exception to "the key is the package's name". A repository publishes major 2 as tags `v2.x.y` at its root or, to keep two majors on one branch, in a `v2/` directory with its own `zs.toml` (Go's two layouts, tried in that order).
- **`zs tree`** shows what was selected and why:

```text
app 0.3.0
├── json 1.3.0          (asked: 1.2 by app, 1.3 by yaml)
│   └── text 0.2.1
├── yaml 0.5.0
└── json/v2 2.1.0       (as json2)
```

### Items 3 to 8

- **Internal modules (item 3):** the files under an `internal/` directory, anywhere in the package, are visible to the package's own files only (Go's rule, no keyword). They are named by path as any file (`src/internal/Lexer.zs` is `Json.Internal.Lexer`); from another package the name doesn't resolve: `Json.Internal.Lexer is internal to json; use its public modules (Json, Json.Parser)`.
- **C dependencies (item 4):** `[c]` holds `sources` (`.c` files compiled by `zig cc`, `.cpp` by `zig c++`, for the target, since `zig cc` targets the host too; objects cached under `.zs-cache/c/<key>/<target>/` by the sources' hashes), `include` (directories added to `import c`'s search and the sources' compile), `link` (`-l` names or files, as `[<Link>]` gives today, d6eb26d lines 311–345), and `pkg-config` (names whose `--cflags` and `--libs` are added for a host build; a cross build takes `[target.<name>.c]` instead, since pkg-config knows the host only). The program's link line is the union, without duplicates. A C++ library gets an `extern "C"` shim in `sources`. The error: `package sqlite: pkg-config knows no 'sqlite3'; install the library's development files, or give include and link in [target.<name>.c]`.
- **Targets (item 5):** a package needs Std when any of its files opens or names a Std module (`Console`, `IO.File`, `Net.Tcp`, …: `stdFiles`, main checkout line 401), read from the summaries the cache keeps for every file anyway (`summaryOf`, facts sheet §9; 0007). A microcontroller build checks every package before checking any module, so the error is first and names the package: `package http needs Std (src/Server.zs uses Net.Tcp), which a cortex-m4 build doesn't have; remove the dependency, or build for a target with an OS`. A package can't declare itself Core-only; the compiler derives it, so the claim is never stale.
- **Integrity (item 6):** the lock's `hash` is SHA-256 over a checkout's files, sorted paths and contents, `.git` left out (Go's directory hash). It's checked when a dependency is fetched and when its files are read for the cache's keys, which hashes them anyway (0007). `zs vendor` copies each dependency into `vendor/<key>/`, hashes checked; a project with `vendor/` reads from it and never fetches. `--offline` fails instead of fetching. `zs new` adds `.zs-cache/` to `.gitignore` (it writes `build/` alone today, `src/Main.fs`, d6eb26d line 141); `vendor/` is committed. The error: `json 1.3.0 doesn't match zs.lock's hash: the tag moved, or .zs-cache/deps/json was edited; zs fetch restores the locked files, zs update json accepts the new ones`.
- **Commands (item 7):** `zs add json@1.2` writes the dependency (through the index as `json = "1.2"`; `zs add https://github.com/someone/json@1.2` with a URL, the key from the package's manifest; `zs add ../text` for a path), fetches, resolves and writes the lock. `zs remove json` deletes the line and resolves again. `zs tree` prints the selection above. The error: `zs remove yaml: zs.toml has no dependency 'yaml' (it has json, text)`.
- **Workspaces (item 8):** `[workspace] members = ["cli", "lib/*"]` in a root `zs.toml`: one `zs.lock` and one `.zs-cache/` at the root, members as path dependencies of one another, `zs build` and `zs test` at the root over every member, `zs add` and `zs remove` in a member editing its manifest and the root lock. The error, for a lock inside a member: `cli/zs.lock belongs to the workspace at ../zs.toml, which has the one lock; delete it and run zs fetch at the root`.

### The index and the first-party packages

Track K's rule is **wrap before writing:** a community that writes and maintains large
libraries in Z# isn't coming soon, so a package first wraps a proven C library (or a C++ one
through its C API) and is Z# only as the typed, idiomatic layer on top. A package is written in
Z# from scratch when no fitting library exists, or when the wrapper would be bigger than the
code. **Choosing a library:** a permissive license, a C API, and a build with `zig cc` for
every target with an OS, macOS included; one that also builds for Cortex-M is preferred
(mbedTLS over OpenSSL). First-party packages live under `zsharp/`, kept building by the
compiler's CI.

| Package | Wraps | Gives | When |
|---|---|---|---|
| `zsharp/index` | nothing: a git repository with one file per name, listing each version's URL, commit and hash | `json = "1.2"` and `zs add json@1.2`, read through a shallow clone under `~/.cache/zs/index` that `zs update` refreshes; `zs publish` pushes the tag `v<version>` and opens a pull request adding the entry | later, when names are worth having; after the ownership question |
| `zsharp/libclang` | libclang's C API | `import c` without `clang -ast-dump=json`, the 10,000-deep JSON and the macro regexes ([0020](0020-self-hosting.md)) | before phase 11, pinned by `rev` until item 2 |
| `zsharp/xxhash` | xxHash, one C header | the cache's keys in place of SHA-256 ([0007](0007-incremental-builds.md), 0020) | before phase 11, as above |
| `zsharp/http` | llhttp | a client and a server on `Net.Tcp` and `Task`; `examples/echo` rebuilt on it serves HTTP (exit test) | after phase 11 |
| `zsharp/regex` | PCRE2 | regular expressions; the compiler's two remaining uses | after phase 11 |
| `zsharp/tls` | mbedTLS | TLS over `Net.Tcp`; builds for Cortex-M | after phase 11 |
| `zsharp/sqlite` | SQLite | a database after nothing more than `zs add` (exit test); rows for 0001's `sql` provider | after phase 11 |
| `zsharp/raylib` | raylib | games over C libraries (decision 30); `examples/raylib` uses `[<Link>]` today | after phase 11 |
| `zsharp/cli` | nothing: Z# | argument parsing derived from a record, the one written from scratch | after phase 11 |

### Order of implementation

1. **Item 1,** before phase 11: the names, lookup by key, Core's qualified names, the cache's keys. `tests/project/` gains a program with two dependencies that both have a `Util.zs`; `tests/project/wc` and `tests/project/git.sh` pass unchanged (`Text.wordCount` is `text`'s root). The guide's Projects section and DESIGN §12 follow.
2. **Item 2,** first after phase 11, since the first-party packages after it want versions (the ordering rationale): `version`, `ls-remote`, selection, the lock's `version`, `zs update`'s new meaning. `git.sh` gains the diamond over two local repositories and `json` with `json2`.
3. **Items 7 and 6:** `zs add`, `zs remove`, `zs tree`; then `hash`, `zs vendor`, `--offline`, so the lock's form changes once.
4. **Item 4,** with `zsharp/sqlite` as its test.
5. **Items 3 and 5:** both read a package's file list and summaries; small.
6. **Item 8.**
7. **The index,** after a design review settles ownership.

Each step keeps `./test.sh` green; a new `.sh` test needs its stanza (facts sheet §14).

## Drawbacks

- **Item 1 breaks dependents** that use a dependency's non-root modules unqualified. That's why it's first.
- **Minimal versions are old versions.** A program gets the oldest version that satisfies everyone, not the newest; a fix in `json` 1.3.1 reaches a program only through `zs update`. Go lives with this; `zs tree` shows what's behind.
- **No renaming:** a key is the package's name, so a program can't call `json` by another name, except for a second major.
- **`pkg-config` knows the host,** so a cross build needs its flags written by hand in `[target.<name>.c]`.
- **Hashing costs a read** of every dependency file, at fetch and when the cache's keys are computed.
- **An index is pull requests:** a human merges, and ownership of a name is a policy before it's a mechanism.
- **More driver:** manifest, resolution, the C compile, vendoring and workspaces are all code the compiler in Z# carries over ([0020](0020-self-hosting.md)).

## Alternatives

- **SemVer ranges with a solver** (Cargo, NuGet, npm): `>=1.2, <1.5` is expressible, and the solver finds the newest set that fits. It needs a solver, whose answer changes as versions are published unless a lock pins it, so the lock becomes the truth instead of the manifests. Not chosen: minimal version selection gives the same answer from the manifests alone, and Go has shown the restriction is livable.
- **A registry service** (crates.io, nuget.org): hosts code, serves an API, verifies ownership with accounts. Someone runs it, pays for it, and keeps it up. Not chosen: git URLs need no service, and an index as a repository gives names later without one.
- **Binary packages:** decision 27; there is no IR format to version, and closed source ships as a C library.
- **Go's module proxy and checksum database:** a cache of every module and a transparency log of hashes. Not chosen: that is the service above; the lock's hash protects a project and `vendor/` protects a repository.
- **A keyword for internal modules** (`internal` as in C#): new syntax under decision 34 for what a directory name says. Not chosen.
- **A build script** (Cargo's `build.rs`): code that runs at build time, against the spirit of decision 20, and more than a wrapper needs. Not chosen: a declarative `[c]` covers wrapping, which is what packages are.
- **Several versions of one major in a build** (npm's nested `node_modules`): no diamond is ever a conflict, and a `Json.Json` from one copy doesn't unify with the other's. Not chosen: one version per major, as Go and Cargo do.
- **A `core-only = true` declaration** for microcontroller packages: a claim that goes stale. Not chosen: the compiler derives it from the files.

## Compatibility

- **Item 1 is breaking** for a program that uses a dependency's non-root modules unqualified (`Util.f` where `Util.zs` is in the dependency): write `Json.Util.f`, or `open Json`. A dependency whose `main` is its only module keeps working: `tests/project/wc`'s `Text.wordCount`. The cache's keys change once.
- **Everything else is additive.** A manifest without `version`, `[c]`, `[target]` or `[workspace]` means what it means today; today's `zs.lock` entries are read and rewritten in the new form at the next resolution.
- **An older compiler** stops at `[c]`, `[target.cortex-m4]` or `[workspace]` with `unknown section [c]` (d6eb26d line 110). It ignores `version` next to `git` and checks out the default branch (`rev` defaults to the empty string, line 108), so a new manifest builds something else on an old compiler; a new lock, however, keeps `git` and `commit`, which the old reader takes (line 200), so a project with its lock committed builds the locked commits.
- **Compiled binaries:** none to consider; packages are source (decision 27).
- **The library:** unchanged. Its naming by path is what item 1 extends; the namespaces stay open at the lowest precedence.
- **Microcontrollers:** item 5, and `[target.<name>]` from 0014. A Core-only package (`regex` over PCRE2 built for Cortex-M, `tls`) builds for them; `http` and `cli` need Std.
- **Phase 11:** the compiler in Z# depends on `zsharp/libclang` and `zsharp/xxhash` through this mechanism, by `rev` until item 2.

## Pragmatics

### Diagnostics

| Situation | Error |
|---|---|
| a key that isn't a name | `zs.toml:7: dependency 'my json' isn't a name; use letters, digits, - and _` |
| the key isn't the package's name | `zs.toml:7: dependency 'jsonlib' is the package 'json' (its zs.toml says so); name it json` |
| a dependency's non-root module used unqualified (after item 1) | `unknown module 'Util'; did you mean Json.Util?` |
| the main file's `module` header disagrees | `.zs-cache/deps/json/src/lib.zs:1: module Parser; this is json's main file, which is the module Json; drop the header` |
| `rev` and `version` together | `zs.toml:8: dependency 'json' has both rev and version; keep one` |
| no tag satisfies a version | `json: no tag v1.2.0 or later below v2.0.0 (the newest is v1.1.2); write version = "1.1", or ask for a release` |
| two packages under one key | `two dependencies are named 'json': https://a/json and https://b/json; packages have one name per build` |
| an internal module from outside | `Json.Internal.Lexer is internal to json; use its public modules (Json, Json.Parser)` |
| `pkg-config` finds nothing | `package sqlite: pkg-config knows no 'sqlite3'; install the library's development files, or give include and link in [target.<name>.c]` |
| a C source fails to compile | the compiler's own errors, then `in package sqlite, [c] sources` |
| a Std package in a microcontroller build | `package http needs Std (src/Server.zs uses Net.Tcp), which a cortex-m4 build doesn't have; remove the dependency, or build for a target with an OS` |
| a hash mismatch | `json 1.3.0 doesn't match zs.lock's hash: the tag moved, or .zs-cache/deps/json was edited; zs fetch restores the locked files, zs update json accepts the new ones` |
| `--offline` with nothing fetched | `json isn't in .zs-cache/deps/ or vendor/, and --offline forbids fetching; run zs fetch where there is a network` |
| `zs remove` of nothing | `zs remove yaml: zs.toml has no dependency 'yaml' (it has json, text)` |
| `zs add` of a second major under a taken key | `json is at major 1 in zs.toml; add major 2 as json2 = { git = "…", version = "2.1" }` |
| a lock inside a workspace member | `cli/zs.lock belongs to the workspace at ../zs.toml, which has the one lock; delete it and run zs fetch at the root` |
| a name the index doesn't have | `the index has no 'jsno'; did you mean json? or give a git URL: zs add https://…@1.2` |

Every manifest error carries `zs.toml:line`, as `readManifest`'s do today.

### Tooling

- **`zs lsp`:** hover on `Json.Parser.parse` shows `Json.Parser.parse : string -> result<Json, string>`, its `///` comment, and `from json 1.3.0`; completion after `Json.` lists the root's declarations and the package's modules, internal ones left out outside the package; definition opens the file under `.zs-cache/deps/` or `vendor/`; references cross packages. Diagnostics while editing come from the checker's real types with no build run: a dependency that isn't fetched is one error at its first use (`Json isn't fetched; run zs fetch`: the server never fetches, DESIGN §12) and the rest of the file is checked; a manifest error is published against `zs.toml` with its line (today another file's error lands on the open file's first line, facts sheet §1). In a workspace the server resolves an open file through its member's manifest and the root's lock.
- **The tree-sitter grammar** gains nothing: `open Json.Parser` and `Json.Parser.parse` are the qualified identifiers it has (`editors/tree-sitter-zsharp/grammar.js`, main checkout lines 89 and 370), and `zs.toml` is TOML, which editors highlight already.
- **`zs doc`** documents a dependency's modules under their full names; **`zs fmt`** is untouched; **`zs mcp`'s** `check` sees dependencies as the CLI does, and an agent reads `zs tree`.
- **`zs tree`, `zs add`, `zs remove`, `zs vendor`** join `zs fetch` and `zs update` in the usage line.

### Performance

- **A build without changes:** a dictionary lookup per module name, the lock read once, and the hash check on files the cache hashes anyway; nothing at run time (names are names).
- **Resolution:** one `git ls-remote` per package, only when a dependency is new or its line changed, or on `zs update`; selection is linear in the number of dependency lines (estimate: a thousand packages in well under a second without the network).
- **Fetching:** one clone per package, then a tag checkout per new version; `vendor/` makes it zero.
- **`[c]` sources:** compiled once per source per target and cached by hash; a cross build compiles them again for its target.
- **Item 1** rebuilds every cached result once, at the upgrade (the keys change).

### Scaling

| Dimension | Typical | Upper bound |
|---|---|---|
| dependencies in a manifest | 3–10 | 300 |
| packages in a build, transitively | 5–30 | 1,000 |
| tags per package | 10 | 1,000 (listed once per resolution) |
| files per package | 5–50 | 1,000 (named by path, found by prefix) |
| a checkout's size to hash | 1 MB | 100 MB (read once at fetch) |
| workspace members | 2–5 | 100 |
| names in the index | hundreds | 100,000 (one file each, as crates.io's index) |

### Culture-aware formatting and parsing

Invariant throughout: names and versions are ASCII, and a version is digits and dots; manifests
and locks are UTF-8 with `/` as the path separator whatever the host (the target's at run time
is [0022](0022-targets-macos-windows.md)'s rule for `Path`, not the lock's); `zs tree` prints
versions and names as written, with no grouping or locale.

## Unresolved questions

1. **Version syntax:** `version = "1.2"` meaning 1.2.0 or later within the major (this proposal, Go's reading), against Cargo's operators (`"^1.2"`, `">=1.2, <1.5"`). Operators invite ranges, which invite a solver.
2. **Whether `main`'s module must be named after the package:** the main file is the root whatever its file name, and a `module` header in it must agree or be absent (this proposal), against requiring the file to be named `<Name>.zs`, which says less and forces `tests/project/text`'s layout on everyone.
3. **Whether a key may rename a package:** no, except for a second major (this proposal), against an alias per importer (Go's `import j "…/json"`), which costs a map from (importer, key) to the package in every lookup and in every error message.
4. **How the index verifies ownership of a name:** the first pull request that adds a name records the git host account that opened it, and later changes to that name must come from that account or one it lists (this proposal), against naming packages by their host path (`github.com/someone/json`), which needs no ownership and no index at all, at the cost of `json = "1.2"`.
5. **The lock's hash:** SHA-256 over the files (this proposal), which the compiler in Z# must then implement or take from `zsharp/tls`, against trusting the git commit (SHA-1, and gone once vendored).
6. **A provider package's `[provider]` section** ([0001](0001-type-providers.md), its question 3): `[provider] name = "svd"  main = "src/provider.zs"`, built by `zs` before use, with its version in the cache key (sketched here), against providers only on PATH.

## History

- **2026-10-22:** drafted from track K's plan (ROADMAP, commit d6eb26d), DESIGN §12's Projects and the guide's Projects section; item 2 and the index need a new decision row, numbered by the coordinator.
