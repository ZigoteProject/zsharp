#!/usr/bin/env bash
# Builds the compiler, then checks every tests/**/*.zs that has an expected .out (run output) or
# .err (compile error) next to it; other .zs files are modules those tests use.
# --valgrind: also run each program under valgrind (memory errors or leaks fail the test).
set -u
cd "$(dirname "$0")"
dotnet build src -c Release -o bin --nologo -v q || exit 1
export ZS_LEAKCHECK=1 ZS_BACKTRACE=0  # report leaked objects at exit; deterministic panic output
valgrind=0; [ "${1:-}" = "--valgrind" ] && valgrind=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
for t in $(find tests -name '*.zs' | sort); do
  base=${t%.zs}
  [ -f "$base.out" ] || [ -f "$base.err" ] || continue
  if [ -f "$base.err" ]; then
    # compare the error lines, not the source snippets under them
    actual=$(bin/zs build "$t" -o "$tmp/exe" 2>&1 | grep -v '^ [ 0-9]* | '); expected=$(cat "$base.err")
  elif ! bin/zs build "$t" -o "$tmp/exe" 2>"$tmp/build.log"; then
    actual=$(cat "$tmp/build.log"); expected=$(cat "$base.out")
  else
    run=("$tmp/exe")
    # panics abort without cleanup by design, so only exit-normally programs are leak-checked
    [ $valgrind = 1 ] && ! grep -q "^panic:" "$base.out" && run=(valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99 "$tmp/exe")
    actual=$("${run[@]}" < /dev/null 2>&1); code=$?
    expected=$(cat "$base.out")
    [ $code = 99 ] && actual="$actual
(valgrind reported memory errors or leaks)"
  fi
  # base.same-ir names another program that must compile to identical LLVM IR
  if [ -f "$base.same-ir" ]; then
    other=$(cat "$base.same-ir")
    bin/zs build "$t" -o "$tmp/a" --emit-llvm >/dev/null 2>&1; bin/zs build "$other" -o "$tmp/b" --emit-llvm >/dev/null 2>&1
    cmp -s "$tmp/a.ll" "$tmp/b.ll" || actual="$actual
(LLVM IR differs from $other)"
  fi
  if [ "$actual" == "$expected" ]; then echo "ok   $t"
  else echo "FAIL $t"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi
done
# the prelude checks on its own (an editor opening it must not see everything defined twice)
if bin/zs check runtime/prelude.zs >"$tmp/prelude.log" 2>&1; then echo "ok   zs check runtime/prelude.zs"
else echo "FAIL zs check runtime/prelude.zs"; head -5 "$tmp/prelude.log"; fail=1; fi

# the repository's own Z# code is formatted (zs fmt)
if bin/zs fmt --check $(find tests runtime -name '*.zs') 2>"$tmp/fmt.log"; then echo "ok   zs fmt --check"
else echo "FAIL zs fmt --check (run: bin/zs fmt \$(find tests runtime -name '*.zs'))"; cat "$tmp/fmt.log"; fail=1; fi

# the language server: a scripted session (tests/lsp/session.sh) against its expected transcript
actual=$(tests/lsp/session.sh bin/zs 2>&1); expected=$(cat tests/lsp/session.out)
if [ "$actual" == "$expected" ]; then echo "ok   tests/lsp/session.sh"
else echo "FAIL tests/lsp/session.sh"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi

# editors may start zs without arguments: it detects LSP or MCP from the first byte
printf '#!/bin/sh\nexec %s/bin/zs\n' "$PWD" > "$tmp/zs-bare"; chmod +x "$tmp/zs-bare"
if [ "$(tests/lsp/session.sh "$tmp/zs-bare" 2>&1)" == "$(cat tests/lsp/session.out)" ] \
   && [ "$(tests/mcp/session.sh "$tmp/zs-bare" 2>&1)" == "$(cat tests/mcp/session.out)" ]; then echo "ok   zs without arguments (protocol detection)"
else echo "FAIL zs without arguments (protocol detection)"; fail=1; fi

# the MCP server: a scripted session (tests/mcp/session.sh) against its expected transcript
actual=$(tests/mcp/session.sh bin/zs 2>&1); expected=$(cat tests/mcp/session.out)
if [ "$actual" == "$expected" ]; then echo "ok   tests/mcp/session.sh"
else echo "FAIL tests/mcp/session.sh"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi

# editor support: the Zed extension's queries are copies of the grammar's; the grammar parses
# every program without errors (needs the tree-sitter CLI and a C compiler)
if diff -q <(cat editors/tree-sitter-zsharp/queries/*.scm) <(cat editors/zed/languages/zsharp/*.scm) >/dev/null; then
  echo "ok   editors/zed queries"
else echo "FAIL editors/zed queries differ from editors/tree-sitter-zsharp/queries"; fail=1; fi
if command -v tree-sitter >/dev/null; then
  ts=$(editors/tree-sitter-zsharp/script/errors.sh 2>&1)
  if [ "$(echo "$ts" | tail -1)" = "files with errors: 0" ] && (cd editors/tree-sitter-zsharp && timeout 60 tree-sitter test >/dev/null 2>&1); then
    echo "ok   editors/tree-sitter-zsharp"
  else echo "FAIL editors/tree-sitter-zsharp"; echo "$ts" | tail -20; fail=1; fi
else echo "skip editors/tree-sitter-zsharp (no tree-sitter CLI; rebuild the dev image)"; fi

# C interop: a directory with main.c links the static library built from its lib.zs
for c in $(find tests -name main.c | sort); do
  d=$(dirname "$c")
  if bin/zs build "$d/lib.zs" --lib -o "$tmp/lib.a" 2>"$tmp/build.log" && clang -I"$tmp" "$c" "$tmp/lib.a" -lm -o "$tmp/cexe" 2>>"$tmp/build.log"; then
    run=("$tmp/cexe"); [ $valgrind = 1 ] && run=(valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99 "$tmp/cexe")
    actual=$("${run[@]}" 2>&1); [ $? = 99 ] && actual="$actual
(valgrind reported memory errors or leaks)"
  else actual=$(cat "$tmp/build.log"); fi
  expected=$(cat "$d/main.out")
  if [ "$actual" == "$expected" ]; then echo "ok   $c"
  else echo "FAIL $c"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi
done
exit $fail
