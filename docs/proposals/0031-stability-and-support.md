# Proposal 0031: stability and support

| | |
|---|---|
| **Status** | Draft |
| **Decided at** | not yet: a design review, before the release after 0.7.1 |
| **Builds** | after 0.7; the 1.0 gate when its list is met |
| **Rests on** | [README](../../README.md) ("No stability yet"); [release](../contributing/release.md) (pre-1.0); [SECURITY.md](../../SECURITY.md) (supported versions); track S's freeze at 1.0 ([ROADMAP](../../ROADMAP.md#library-s)); decision 61 (warnings, `deprecated`) |
| **Related** | [0021 warnings](0021-warnings.md) (`[<Deprecated>]`), [0024 the library's API](0024-library-api.md) (the name review), [0018 packages](0018-packages.md) (versions), [0020 the compiler in Z#](0020-self-hosting.md) (stage 0), [0022 targets](0022-targets-macos-windows.md) |
| **Changes** | README's status; `SECURITY.md`'s supported versions; `docs/contributing/release.md`; `CHANGELOG.md`'s form; `test.sh` (two checks); no language change |

- [ ] Approved in principle
- [ ] Discussion
- [ ] Implementation

## Summary

Today the whole promise is one sentence: releases before 1.0 may break source, and
`CHANGELOG.md` says what to rewrite. That's honest and not enough to build on: a team can't
tell what a patch release may change, which platforms are held to what, how long a release
gets fixes, or what has to be true before 1.0. This proposal writes those four down, and adds
the two checks that keep them true:

1. **What a version number means,** from the next release on: a patch never breaks source; a
   minor breaks it only after a release that warned.
2. **What the promise covers** (the language, the library's public names, the manifest, the
   lock and the command line) and what it doesn't (diagnostics' wording, generated code,
   `Native`, anything under `unsafe`).
3. **Target tiers:** which platforms a release is tested on, and how.
4. **Support:** which releases get fixes, and how fast a security or miscompilation fix ships.
5. **The 1.0 gate:** a list of facts, each checkable, in place of a date.

## Motivation

**A patch that breaks.** 0.7.1 is a patch by its number and took `break`, `continue` and
`return` as keywords: a 0.7.0 program with a value named `return` stopped compiling. The
changelog said so, and nobody was hurt because nobody had such a program. With users, the same
release is a service that can't take a security fix without a rewrite. The security fixes and
the keywords were one release because there was no rule that said they couldn't be.

**Which platform is real.** The README lists nine targets. Six have the suite passing in CI
at each push; two chips and WebAssembly run under an emulator on one of them; the board hasn't
been flashed. All of that is in the roadmap's prose and none of it is in a table a user would
find before choosing a platform.

**How long.** `SECURITY.md` supports "the latest release", with fixes in "the next release".
The next release is whenever it's ready, with whatever else is in it.

**When is 1.0.** "1.0 freezes the language and the library" appears in three files. What must
be true first appears in none, so it can't be worked toward or argued with.

## Design

### 1. Version numbers

From the release after this proposal is taken, for `0.N.P`:

- **A patch (`P`) changes no meaning.** A program that built with `0.N.0` under `--strict`
  builds with every `0.N.P` and prints the same. A patch holds fixes: security, a
  miscompilation, a crash of the compiler, a wrong diagnostic, a platform. No new keyword, no
  renamed or removed library name, no new warning (a new warning breaks `--strict`).
- **A minor (`N`) may break source, after a warning.** A name to be renamed or removed is
  marked `[<Deprecated "use X">]` in one minor and goes in the next, so a program that builds
  without warnings on `0.N` builds on `0.N+1`. What can't be warned about ahead (a new
  keyword, a changed meaning) is listed under **Upgrading from** in that release's notes,
  each with what to rewrite, as today.
- **One exception, at any level: soundness.** A program that was accepted and could read or
  write memory it doesn't own, race, or overflow silently is rejected by the fix, in a patch.
  The notes name it.
- **After 1.0** the minor's rule becomes the major's: `1.x` to `1.y` breaks nothing but the
  exception; a deprecated name stays until 2.0.

This needs [0021](0021-warnings.md)'s `deprecated` warning built now, not at the freeze. It's
the one piece of code in this section.

### 2. What the promise covers

| Covered | Its definition |
|---|---|
| the language | [the specification](../spec/README.md): a paragraph not marked *Implementation* or *Deviation* |
| the library | every public name of the prelude, Core and Std with a page in [the reference](../reference/README.md): its type and what its doc comment says |
| projects | `zs.toml`'s keys and `zs.lock`'s format: an older file is read by a newer `zs` |
| the command line | `zs`'s commands, their flags and exit codes |
| C | what a `[<Export>]` or `--lib` build exposes: names, layouts ([0004](0004-c-layout.md)) and the header |
| protocols | the type provider protocol ([0001](0001-type-providers.md)); the MCP tools' names and arguments |

Not covered, and free to change in a patch:

- **A diagnostic's wording** and how many are reported. Its being an error or a warning is
  covered.
- **Generated code:** speed, size, layout of a type without `[<CLayout>]`, the order
  allocations happen in, what `--emit-llvm` prints. `bench/host` guards speed; it's a check,
  not a promise.
- **`Native`, the runtime's symbols (`zs_…`)** and anything a program reaches only through
  `unsafe` or `extern`.
- **The cache** (`.zs-cache/`) and the build server's protocol: both are rebuilt by the `zs`
  that reads them.
- **Formatting:** `zs fmt` may format a file differently in a minor, never in a patch (a
  patch would fail a project's own format check).
- **A panic's message and a backtrace's form.**

### 3. Target tiers

| Tier | Means | Today |
|---|---|---|
| 1 | the whole suite passes on the platform's own machine at each push; every release ships an archive, installed on a clean machine before it's announced | Linux x86-64 and arm64; macOS arm64 and x86-64; Windows x64 and arm64: once phase 11.5's clean-machine installs are done |
| 2 | the target's programs build and run under an emulator in a tier 1 suite | Cortex-M4 and M0+ (QEMU), `wasm32` (Node) |
| 3 | builds; run by hand, or not yet | the Nucleo-F401RE until it's flashed (phase 12) |

A defect on tier 1 blocks a release. One on tier 2 blocks it if the emulator shows it. Tier 3
is listed so nobody reads the target list as a promise. The table lives in the README; a
target moves up by the roadmap's exit tests, never by an edit alone.

### 4. Support

- **Before 1.0, the latest minor is supported.** A security defect (as `SECURITY.md` defines
  one) or a miscompilation gets a patch release on it, holding only fixes, within 14 days of a
  confirmed report: not "the next release".
- **After 1.0, the latest two minors,** the older for six months after the newer's release.
- **A patch is built from a branch** (`release/0.N`) cut at `0.N.0`, so `master` taking a
  breaking change doesn't hold a fix back. Fixes land on `master` first and are picked onto
  the branch.
- **Each release's notes say what it was tested on:** the suite's counts per runner, as
  0.7.1's do.

### 5. The 1.0 gate

1.0 is released when each of these is true, and not before:

1. **Verification closed:** phases 11.5 and 12 (clean machines, the board); the stress run
   over the pool, tasks and `Alt` under ThreadSanitizer with no finding.
2. **The specification matches:** no *Deviation* paragraph left, or each one taken as the
   design by a decision row.
3. **The language's gaps decided:** every item of track G implemented or declined;
   [0028](0028-written-constraints.md) built, since packages publish signatures.
4. **The library's names reviewed** against .NET and F# ([0024](0024-library-api.md), track
   S's freeze), the renames shipped as deprecations one minor before.
5. **The known holes in shipped features closed or documented as the design:** a `use` under a
   resumption never called and under a stop in a `task { }` (S10).
6. **The packages a service needs exist:** `http`, `tls` and `sqlite`
   ([0032](0032-first-party-packages.md)) at their own 1.0.
7. **A program has run:** one service not written for the suite, serving for 90 days on a
   release, with what it found fixed. `bench/echo/soak.sh` is the rehearsal, not the test.
8. **Two minors in a row** went out with an empty **Upgrading from** section.
9. **The bootstrap is recoverable:** every release's archives and their SHA-256 are in a
   second place than the repository's releases, and the chain from a released compiler to
   `master` is a documented sequence of builds.

### 6. The two checks

A promise without a check is prose (rule 1 of [AGENTS.md](../../AGENTS.md)).

- **`tests/compat.sh`: programs frozen at each release.** `tests/compat/0.N/` holds programs
  and their `.out`, copied from the suite when `0.N.0` is cut and never edited after. The
  suite builds them with `--strict` and compares. On a patch branch all of them must pass; on
  `master` a failing one is moved to `tests/compat/0.N/broken/` in the commit that breaks it,
  with a line in `CHANGELOG.md`'s **Upgrading from**: the check fails if a program is moved
  without that line.
- **`tests/api.sh`: the library's names.** `zs doc` already walks every public name. The check
  writes them with their types, one per line, and compares with `tests/api/0.N.txt`, the list
  at the last minor. A name missing or of another type fails unless the last minor marked it
  `[<Deprecated>]`. A new name passes.

Both are scripts with expected files, in the suite's existing form. Neither needs a new tool.

### Order of implementation

1. The README's tier table, `SECURITY.md`'s support paragraph, `release.md`'s rules: text.
2. `[<Deprecated>]` and its warning (0021).
3. `tests/api.sh`, with 0.7's list as the first baseline.
4. `tests/compat.sh`, with 0.7's corpus.
5. The `release/0.N` branch, at the next minor.

## Drawbacks

- **Slower change.** A rename takes two minors. The language is still finding its gaps (track
  G lists them), and each fix that changes meaning now costs an **Upgrading from** line and
  a moved test. That cost is the point, and it's real.
- **Two branches for one maintainer.** A patch branch is work per fix. It's bounded: one
  supported minor before 1.0.
- **The corpus grows** by a copy of part of the suite per minor. Only programs, no scripts:
  small files.

## Alternatives

- **Stay as it is until 1.0.** No cost now. But the first user who's broken by a patch learns
  the rule from the breakage, and 1.0 arrives with no practice at keeping a promise.
- **Editions** (Rust's): a file or a project names the language version it's written in, and
  the compiler keeps every edition's meaning. It removes the trade between fixing and
  keeping, at the price of every pass carrying each edition's rules for ever. Not for a
  compiler of 36,000 lines and one maintainer; nothing here rules it out after 1.0.
- **A fixing tool** (`zs fix`, as `go fix`): rewrites a program across a break. The lossless
  syntax tree ([0019](0019-syntax-tree.md)) makes it possible. Not proposed: no break so far
  has been large enough to want one. Worth it the first time an **Upgrading from** entry
  needs more than a rename.
- **Semantic versioning to the letter:** pre-1.0 means anything may change, and that's the
  standard reading. It's what the README says now.
- **A long-term-support release.** After 1.0, if a user asks.

## Compatibility

Nothing breaks: this proposal limits what later releases may break. `[<Deprecated>]` is a new
attribute and a new warning, so a program that uses the name `Deprecated` for an attribute of
its own (none can: attributes aren't user-defined) is unaffected.

## Pragmatics

- **Diagnostics:** the `deprecated` warning names the declaration, its message and the use:
  `warning[deprecated]: Int.ofString is deprecated: use Int.parse`. `[<NoWarn "deprecated">]`
  silences it where a library must call its own old name.
- **Tooling:** the LSP shows the warning as struck-through text (the protocol's `Deprecated`
  tag) and offers the replacement when the message has the form `use X`.
- **Performance, scaling:** two scripts in the suite, each a build of small programs.
- **Packages:** a package's own version follows [0018](0018-packages.md): a major is another
  package, so the rule for packages is already stricter than this one.

## Unresolved questions

1. **14 days** for a fix: is it a promise one maintainer can keep? An honest "best effort,
   with the date in the advisory" may be better than a number that slips.
2. **Does the gate's item 7 need to be someone else's program?** The twelve-dollar server is
   the author's. A stranger's is stronger evidence and can't be scheduled.
3. **Which programs go into the corpus:** the whole of `tests/*.zs`, or the guide's examples
   (what users copy) and `examples/`?
4. **`zs fmt` in a minor:** a project that checks formatting in CI is broken by it. Pin the
   style at 1.0, or version it in `zs.toml`?
5. **The second place for the archives** (item 9): which, and who pays for it.
6. **Does the MCP server belong in the promise** before agents have used it for a release or
   two?

## History

- 2026-11-12: written after 0.7.1, from the question of what production use needs.
