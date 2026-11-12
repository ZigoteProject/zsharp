# Contributing to Z#

Thank you for helping. Z# is pre-1.0, so bug reports, small programs that fail and corrections
to the documents are all useful.

## Start here

1. **[AGENTS.md](AGENTS.md):** the repository's map, the commands, the safety rules and the rules
   for a change, on one page. It's for people as much as for agents.
2. **[docs/contributing](docs/contributing/README.md):** a page per topic: development, testing,
   code style, packages, security, releases, documentation and more.

```sh
./dev ./test.sh        # build the compiler in the dev container (podman) and run every check
```

## Ways to contribute

| You have | Do |
|---|---|
| a bug | open an issue with `zs --version`, the platform and the smallest program that shows it |
| a vulnerability | report it privately: [SECURITY.md](SECURITY.md). Not a public issue |
| a fix | a pull request with a test that fails without it |
| a library function | an issue first, to agree its name and tier (Core or Std); then code, doc comment and test |
| a language idea | an issue describing the problem. A change to the language starts as a [proposal](docs/proposals/README.md), not as code |
| a correction to the docs | a pull request; the guide's examples are run by the suite |

## A pull request

- One change, with its test and its documentation
  ([the checklist](docs/contributing/README.md)).
- `./dev ./test.sh` passes locally; CI's six jobs pass before a merge.
- The commit message is a sentence saying what the program now does
  ([commits](docs/contributing/code-style.md#commits)). No trailers.
- No personal information in code, tests, docs or commit messages.
- Say in the description what you tested and what you didn't.

Before large work, open an issue: [ROADMAP.md](ROADMAP.md) says what's planned and in what
order, and a design may already exist.

## License

Contributions are under the repository's [MIT license](LICENSE). Code you didn't write (a
vendored C library) comes with its own license file beside it and a line in the README's License
section.
