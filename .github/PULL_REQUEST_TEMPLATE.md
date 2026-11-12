<!-- One change a pull request. Rules: AGENTS.md; detail: docs/contributing/. -->

## What changes

<!-- What the program, library or tool now does, from the user's side. Link the issue or proposal. -->

## Why

## How it was tested

<!-- Which tests were added, what was run (./dev ./test.sh, --valgrind, --sanitize, --release,
     --target …) and what was not. -->

## Checklist

- [ ] It has a test that fails without the change, and `./dev ./test.sh` passes
- [ ] No expected file, baseline or platform marker was changed just to make a check pass
- [ ] A user-visible change is in `CHANGELOG.md`; a breaking one says what to rewrite
- [ ] The guide, the specification and `DESIGN.md` say what the code now does
- [ ] New public library names have `///` comments, and `docs/reference/` is regenerated
- [ ] A grammar change has its generated parser, its queries and its Zed pin
- [ ] Input from outside (files, packages, sockets, requests) is validated; new `unsafe` is small and explained
- [ ] New downloads or actions are pinned and checksummed
- [ ] No secrets or personal information in code, tests, docs or commit messages
