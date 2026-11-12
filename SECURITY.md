# Security policy

## Reporting a vulnerability

Report it privately through GitHub:
[Report a vulnerability](https://github.com/ZigoteProject/zsharp/security/advisories/new)
(the repository's **Security** tab). Don't open a public issue or pull request for a defect
someone could exploit.

Include:

- the version (`zs --version`) and the platform
- the smallest program, input or project that shows it
- what happens, and what you expected

## What counts

Z# is pre-1.0 and not production-ready, but these are security defects in any release:

- **Safe code breaking memory safety:** a program with no `unsafe` and no `extern` that reads or
  writes memory it doesn't own, races, or overflows silently.
- **The tools running or writing what they shouldn't:** `zs lsp` or `zs mcp` running a project's
  code without `--trust`; a package or manifest making `zs` write outside its directories; the
  build server acting on a request it should refuse.
- **The library mishandling hostile input:** a parser, decoder, process or file function that
  crashes, hangs or corrupts memory on input a program reads.
- **The release and CI chain:** an unverified download, a credential exposed.

Not security defects: a leak through a reference cycle, a panic ending the process, and anything
that needs `unsafe` or a C library to go wrong. These are documented behavior.

## Supported versions

The latest release. Fixes land on `master` and ship in the next release, with a line under
*Security and stability* in [CHANGELOG.md](CHANGELOG.md).

How the code is kept safe, and the trust model:
[docs/contributing/security.md](docs/contributing/security.md).
