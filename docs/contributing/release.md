# CI and releases

What CI runs on each push, how versions are numbered, and how a release is cut.

## CI

One workflow, [`.github/workflows/test.yml`](../../.github/workflows/test.yml), on every push and
pull request. Two stages:

```
linux-x86_64 ── ./dev ./test.sh ── src/release.sh build/zs ci <5 targets> ── upload dist/zs-ci-*
      │
      └─► native (matrix): macOS arm64, macOS Intel, Windows x64, Windows arm64, Linux arm64
            unpack its own archive ── smoke test ── ./test.sh --zs dist/<archive>/zs
```

| Job | Does |
|---|---|
| `linux-x86_64` | fetches stage 0, builds the compiler in the dev container, runs the whole suite (the bootstrap, the chips under QEMU and WebAssembly under Node included), then cross-builds a release archive for every other platform |
| `native` (five runners) | installs clang 23 and zig, unpacks the archive built for it, runs `zs --version`, `zs doctor` and one build with timeouts, then the suite with that compiler |

- **A cross-built compiler is tested where it runs:** each native job's suite includes
  `tests/bootstrap.sh`, the compiler building itself to the same bytes on that platform.
- **A job's limit is 180 minutes;** a suite takes 15 to 80.
- **Green means all six jobs.** The Linux x86-64 job passing alone isn't a tested change.
- **Changing the workflow:** pin actions by commit hash, check downloads against a SHA-256,
  keep `permissions: contents: read` ([security](security.md#scripts-and-ci)). The LLVM version
  is in four places that move together: the Containerfile, and the workflow's macOS, Windows and
  Linux arm64 steps.

There is no deploy step. A release is cut by hand, below.

## Versions

- **Pre-1.0.** A release may break source; `CHANGELOG.md` says what to rewrite. 1.0 freezes the
  language and the library's names.
- **`0.x.0`** is a planned release: a set of roadmap items with exit tests. **`0.x.y`** fixes and
  finishes the one before it.
- **The version is in two places** that must agree: `src/zs.toml` (`version`) and
  `src/Build/Tools.zs` (`let version`, what `zs --version` prints). `src/release.sh` refuses a
  numbered release when they differ.
- **Tags** are `v<version>` (`v0.7.0`).

## Cutting a release

1. **Everything green:** the suite in the dev container, then CI's six jobs on the commit. For a
   release, also run the modes CI doesn't: `./dev ./test.sh --valgrind`, `--sanitize`,
   `--release`. Say in the changelog which were run.
2. **One version commit,** named `<version>: …`, with:
   - `src/zs.toml` and `src/Build/Tools.zs`: the version
   - `CHANGELOG.md`: the release's section (below)
   - `README.md` (status line, the install commands), `docs/spec/README.md` (the language
     version), the guide where it names a version, `ROADMAP.md` (where things stand)
   - `src/ARCHITECTURE.md`: an *In \<version\>* note where modules changed
   - the expected files that print the version (under `tests/lsp/`)
3. **Build the archives** from a clean tree, in the container:

   ```sh
   ./dev bash -c 'src/release.sh build/zs 0.7.1 aarch64-macos x86_64-macos x86_64-windows-gnu aarch64-windows-gnu aarch64-linux-gnu'
   ```

   It builds `src/` three times (by the given compiler, by that build, by that one), requires the
   last two to be the same bytes, and writes `dist/zs-<version>-<os>-<arch>.tar.gz` per platform.
   It refuses when `src/`, `lib/` or `runtime/` hold anything git doesn't, or when the binary
   reports another version.
4. **Tag** the commit `v<version>` and attach the archives to a GitHub release of that tag.
   `./dev` and CI fetch stage 0 from `releases/download/v<version>/<archive>`, so the names must
   be `release.sh`'s.
5. **Keep `dist/`.** It isn't in git, and a later stage 0 may be taken from it.

Not yet verified for any release: the archives on clean macOS and Windows machines, and firmware
on a physical board. The README's status section says so until they are.

## The changelog

`CHANGELOG.md`, newest first. A release's section has, in order:

1. `## <version> (<date>)` and a paragraph: what the release is, in plain words.
2. **What was tested, and what wasn't:** which runners, which modes, at which commit.
3. `### Upgrading from <previous>`: each change a program can notice, one bullet each, with
   **To rewrite:** and what to write instead.
4. What's new, by area; then *Security and stability*.

Write an entry with the change, not at release time. It describes behavior from the user's side
(`An integer literal outside its type's range is an error, where 0.7.0 truncated it`), with a
before and after where a line of code shows it.

## Moving stage 0

The compiler's source may use a feature only once stage 0 has it. To move the pin to a newer
release:

1. `dev`: `stage0=<version>` and the archive's SHA-256 in the `sha256` table (one entry per
   architecture that can develop).
2. `.github/workflows/test.yml`: the `gh release download` line.
3. `ROADMAP.md`'s development paragraph.
4. Run the suite from an empty `build/stage0/`.

Move it in a commit of its own, before the commits that use what it brings. Until then, a
feature added to the language can't appear in `src/`, however useful: the tree must always build
from a published release.

## Other pins

| Pin | Where | Moves with |
|---|---|---|
| LLVM (23.1.4) | `.devcontainer/Containerfile` and the workflow, with SHA-256s | each other; then `./dev --rebuild` |
| zig | the Containerfile's package, the workflow's download | a cross-build fix that needs it |
| GitHub Actions | commit hashes in the workflow | a reviewed update |
| the Zed grammar | `editors/zed/extension.toml`'s `rev` | every grammar change, in the commit after it |
