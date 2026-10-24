#!/usr/bin/env bash
# Builds the compiler (src/, by stage 0: the release ./dev provides as $ZS_STAGE0), then checks
# every tests/**/*.zs that has an expected .out (run output) or .err (compile error) next to it;
# other .zs files are modules those tests use. Builds are --strict: the repository's own code has
# no warnings.
# --valgrind: also run each program under valgrind (memory errors or leaks fail the test).
# --target <triple>: cross-compile the programs and C interop tests (zs build --target) and run
#   them under qemu-user, e.g. --target aarch64-linux-musl, or Wine for x86_64-windows-gnu; the
#   host-only tool checks are skipped.
# --build-only: with --target, build every program and C interop test and run none (macOS's,
#   where nothing here runs them); a failed build fails the test.
# --zs <binary>: test that compiler, installed as bin/zs with the library and runtime beside it,
#   instead of building src/.
set -u
cd "$(dirname "$0")"
valgrind=0; target=""; tgt=(); qemu=(); zsbin=""; buildonly=0; syslibs=()
while [ $# -gt 0 ]; do
  case $1 in
    --valgrind) valgrind=1; export ZS_NO_POOL=1 ;; # objects from malloc, so valgrind sees each one
    --target) target=$2; tgt=(--target "$2"); shift
      case $target in
        *-windows-*) qemu=(timeout 120 wine); syslibs=(-lws2_32 -lapi-ms-win-core-synch-l1-2-0)
          export LANG=C.UTF-8 WINEDEBUG=-all XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/zs-xdg-$UID}; mkdir -p "$XDG_RUNTIME_DIR" ;;
        *) qemu=("qemu-${target%%-*}") ;;
      esac ;;
    --build-only) buildonly=1 ;;
    --zs) zsbin=$2; shift ;;
  esac
  shift
done
# Windows, built for or run on (Git Bash): its expected output where a test has a .windows.out,
# \r\n read as \n, and C built with zig cc for mingw-w64, as zs links (clang alone targets MSVC)
windows=0; [[ $target == *-windows-* ]] && windows=1
case $(uname -s) in
  MINGW* | MSYS* | CYGWIN*) windows=1; syslibs=(-lws2_32 -lapi-ms-win-core-synch-l1-2-0) ;;
esac
if [ -z "$zsbin" ]; then
  [ -x "${ZS_STAGE0:-}" ] || { echo "no stage 0 compiler (\$ZS_STAGE0): run the tests through ./dev"; exit 1; }
  mkdir -p build && ZS_NO_SERVER=1 "$ZS_STAGE0" build src/Main.zs --release -o build/zs || exit 1
  zsbin=build/zs
fi
src/install.sh "$zsbin" bin || exit 1
export ZS_LEAKCHECK=1 ZS_BACKTRACE=0  # report leaked objects at exit; deterministic panic output
export ZS_NO_SERVER=1  # each build in its own process (tests/server.sh tests the build server)
export ZS_CHECK_IR=1  # the compiler checks its IR after each pass (zs build --check-ir)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
for t in $(find tests -name '*.zs' | sort); do
  base=${t%.zs}
  [ -f "$base.out" ] || [ -f "$base.err" ] || continue
  # base.host-only: the reason it can't run cross-compiled under qemu-user
  if [ -n "$target" ] && [ -f "$base.host-only" ]; then echo "skip $t ($(cat "$base.host-only"))"; continue; fi
  if [ -f "$base.err" ]; then
    # compare the error lines, not the source snippets under them
    actual=$(bin/zs build --strict "$t" "${tgt[@]}" -o "$tmp/exe" 2>&1 | grep -v '^ [ 0-9]* | '); expected=$(cat "$base.err")
  elif ! bin/zs build --strict "$t" "${tgt[@]}" -o "$tmp/exe" 2>"$tmp/build.log"; then
    actual=$(cat "$tmp/build.log"); expected=$(cat "$base.out")
  elif [ $buildonly = 1 ]; then
    actual=$(cat "$base.out"); expected=$actual
  else
    run=("${qemu[@]}" "$tmp/exe")
    # panics abort without cleanup by design, so only exit-normally programs are leak-checked
    [ $valgrind = 1 ] && ! grep -q "^panic:" "$base.out" && run=(valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99 "$tmp/exe")
    actual=$("${run[@]}" < /dev/null 2>&1); code=$?
    expected=$(cat "$base.out"); [ $windows = 1 ] && [ -f "$base.windows.out" ] && expected=$(cat "$base.windows.out")
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
  [ $windows = 1 ] && actual=${actual//$'\r\n'/$'\n'}
  if [ "$actual" == "$expected" ]; then echo "ok   $t"
  else echo "FAIL $t"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi
done
# the tools (fmt, LSP, MCP, editors, projects, gdb) are checked on the host only
if [ -z "$target" ]; then
# compile time of a mid-sized program, per phase (watched, not enforced)
bin/zs build tests/json.zs -o "$tmp/time-exe" --time 2>"$tmp/time.log" >/dev/null
echo "time tests/json.zs: $(grep -E '^(parse|total)' "$tmp/time.log" | tr -s ' ' | tr '\n' ';' | sed 's/;$//')"

# tasks over sockets: the echo server holding 1,000 connections, stopped by a client (under
# valgrind with --valgrind)
vg=(); [ $valgrind = 1 ] && vg=(--valgrind)
if diff <(tests/task/echo.sh "${vg[@]}" 2>&1) tests/task/echo.expected >"$tmp/echo.diff"; then echo "ok   tests/task/echo.sh (an echo server, 1,000 connections)"
else echo "FAIL tests/task/echo.sh"; cat "$tmp/echo.diff"; fail=1; fi

# threads under ThreadSanitizer: the pool, Atomic, Mutex, Channel and Task.spawn race on nothing
for t in tests/parallel/basics tests/parallel/anythread tests/task/spawn tests/task/cancel; do
  [ $windows = 1 ] && { echo "skip $t.zs under ThreadSanitizer (none for mingw-w64)"; continue; }
  if bin/zs build $t.zs -o "$tmp/tsan" --sanitize=thread 2>"$tmp/tsan.log" && actual=$(timeout 120 "$tmp/tsan" 2>"$tmp/tsan.log") \
     && [ "$actual" = "$(cat $t.out)" ] && ! grep -q ThreadSanitizer "$tmp/tsan.log"; then echo "ok   $t.zs under ThreadSanitizer"
  else echo "FAIL $t.zs under ThreadSanitizer"; head -40 "$tmp/tsan.log"; fail=1; fi
done

# aarch64's intrinsics (Simd.Arm): built for it and run under qemu
if command -v qemu-aarch64 >/dev/null && bin/zs build tests/simd/arm.zs --target aarch64-linux-musl -o "$tmp/arm" 2>"$tmp/arm.log" \
   && [ "$(qemu-aarch64 "$tmp/arm" 2>&1)" = "$(cat tests/simd/arm.expected)" ]; then echo "ok   tests/simd/arm.zs (built for aarch64, under qemu)"
else echo "FAIL tests/simd/arm.zs"; cat "$tmp/arm.log"; fail=1; fi

# the checked library and modules, cached between builds: the same program from the cache
if diff <(tests/cache.sh 2>&1) tests/cache.expected >"$tmp/cache.diff"; then echo "ok   tests/cache.sh (checked library, modules and compiled modules cached)"
else echo "FAIL tests/cache.sh"; cat "$tmp/cache.diff"; fail=1; fi
if diff <(tests/pgo.sh 2>&1) tests/pgo.expected >"$tmp/pgo.diff"; then echo "ok   tests/pgo.sh (profile-guided optimization finds its profile)"
else echo "FAIL tests/pgo.sh"; cat "$tmp/pgo.diff"; fail=1; fi

# host benchmarks against C: a Z# program needing more than 5% more instructions than in
# bench/host/baseline.txt fails (bench/host/run.sh shows times; --update after an improvement).
# Counted as programs are built by default: with the pool, also under --valgrind
if env -u ZS_NO_POOL bench/host/run.sh --check >"$tmp/bench.log" 2>&1; then echo "ok   bench/host (instruction counts within 5% of the baseline)"
else echo "FAIL bench/host"; cat "$tmp/bench.log"; fail=1; fi

# zs test: passing and failing [<Test>] functions, each in its own process (exit 1: some fail)
actual=$(bin/zs test tests/ztest/sample.zs 2>&1); code=$?
if [ "$actual" = "$(cat tests/ztest/sample.expected)" ] && [ $code = 1 ]; then echo "ok   zs test tests/ztest/sample.zs"
else echo "FAIL zs test tests/ztest/sample.zs (exit $code)"; diff <(echo "$actual") tests/ztest/sample.expected; fail=1; fi
# zs test --update rewrites a failing expect test's literal (0009)
if [ "$(tests/ztest/update.sh 2>&1)" = "$(cat tests/ztest/update.expected)" ]; then echo "ok   tests/ztest/update.sh (zs test --update)"
else echo "FAIL tests/ztest/update.sh"; diff <(tests/ztest/update.sh 2>&1) tests/ztest/update.expected; fail=1; fi

# projects: a CLI tool built from zs.toml with a path dependency; zs test over a project; two
# dependencies with a Util.zs each (0018 K1) and one with C code ([c], K4); zs new
zs="$PWD/bin/zs"
proj=$( (cd tests/project/wc && "$zs" build >/dev/null && ./build/wc sample.txt missing.txt; echo "exit $?"
         "$zs" run -- -l sample.txt; printf 'a b\nc\n' | ./build/wc
         cd ../text && "$zs" test | tail -1
         cd ../two && PKG_CONFIG_PATH="$PWD/../cwords" "$zs" run
         cd "$tmp" && "$zs" new demo >/dev/null && cd demo && "$zs" run Z#) 2>&1 )
expected='4 6 29 sample.txt
wc: cannot open missing.txt: No such file or directory
exit 1
4 sample.txt
2 3 6 
2 passed, 0 failed
alpha: the alpha util 9
beta: the beta util module, 4 words
the alpha util / the beta util module / 16
5 15
Hello, Z#!'
if [ "$proj" = "$expected" ]; then echo "ok   projects (zs.toml, path dependency, zs run/test/new)"
else echo "FAIL projects"; diff <(echo "$proj") <(echo "$expected"); fail=1; fi
rm -rf tests/project/wc/build tests/project/two/build

# what for over Iter costs (0017): a for over a Map is Map.iter's loop; loops over an array, a
# list and a string allocate nothing
if [ "$(tests/iter/loops.sh bin/zs 2>&1)" == "$(cat tests/iter/loops.expected)" ]; then echo "ok   tests/iter/loops.sh"
else echo "FAIL tests/iter/loops.sh"; diff <(tests/iter/loops.sh bin/zs 2>&1) tests/iter/loops.expected; fail=1; fi

# the first-party packages: their own tests, with their C through [c] (0018 item 4)
pk=$( (cd packages/xxhash && "$zs" test | tail -1; cd ../libclang && "$zs" test | tail -1) 2>&1 )
if [ "$pk" = "1 passed, 0 failed
1 passed, 0 failed" ]; then echo "ok   packages (xxhash, libclang)"
else echo "FAIL packages"; echo "$pk"; fail=1; fi

# git dependencies against a local repository: tags, branches, zs.lock, zs update, re-fetching
if diff <(tests/project/git.sh 2>&1) tests/project/git.expected >"$tmp/git.diff"; then echo "ok   tests/project/git.sh (git dependencies)"
else echo "FAIL tests/project/git.sh"; cat "$tmp/git.diff"; fail=1; fi

# import c in the editor: hover shows the Z# type, C prototype and header comment; definition
# opens the header. Then the same file checks with clang unavailable, from the saved import.
lspc=$(tests/lsp/cimport.sh)
if echo "$lspc" | grep -q 'point_add : Point -\\u003E Point -\\u003E Point' && echo "$lspc" | grep -q 'Point point_add(Point a, Point b)' \
   && echo "$lspc" | grep -q 'Adds two points' && echo "$lspc" | grep -q '"id":3,"result":{"uri":"file://[^"]*shapes.h"'; then
  echo "ok   tests/lsp/cimport.sh (C hover and definition)"
else echo "FAIL tests/lsp/cimport.sh"; echo "$lspc" | cut -c1-300; fail=1; fi
if PATH=/nonexistent bin/zs check tests/cimport/main.zs >"$tmp/noclang.log" 2>&1; then echo "ok   import c without clang (from .zs-cache)"
else echo "FAIL import c without clang"; head -3 "$tmp/noclang.log"; fail=1; fi

# import c against a real library: the raylib demo builds (it needs a display to run)
if [ -f /usr/include/raylib.h ]; then
  if timeout 60 bin/zs build examples/raylib/main.zs -o "$tmp/raylib-demo" 2>"$tmp/raylib.log"; then echo "ok   examples/raylib (builds against raylib.h)"
  else echo "FAIL examples/raylib"; head -5 "$tmp/raylib.log"; fail=1; fi
else echo "skip examples/raylib (no raylib.h)"; fi

# debug info: gdb on a zs build -g program (breakpoints, arguments, locals, stepping, backtrace)
if command -v gdb >/dev/null && [ $windows = 0 ]; then
  if diff <(tests/debug/gdb.sh) tests/debug/gdb.expected >"$tmp/gdb.diff"; then echo "ok   tests/debug/gdb.sh"
  else echo "FAIL tests/debug/gdb.sh"; cat "$tmp/gdb.diff"; fail=1; fi
else echo "skip tests/debug/gdb.sh (no gdb)"; fi

# the guide's examples build and print what the guide says (docs/guide)
if tests/docs.sh >"$tmp/docs.log" 2>&1; then echo "ok   docs/guide examples ($(tail -1 "$tmp/docs.log"))"
else echo "FAIL docs/guide examples"; cat "$tmp/docs.log"; fail=1; fi

# Std needs an operating system: built for a microcontroller, using it is a compile error
actual=$(bin/zs build tests/mcu/std.zs --target cortex-m4 -o "$tmp/std.elf" 2>&1 | head -1)
if [ "$actual" = "tests/mcu/std.zs:2:15: error: 'File.readAllText' is in IO.File, part of Std, which needs an operating system; this target has none" ]; then
  echo "ok   tests/mcu/std.zs (no Std on a microcontroller)"
else echo "FAIL tests/mcu/std.zs"; echo "$actual"; fail=1; fi

# effects on a microcontroller (no thread-local storage there: the yield state is a global),
# under qemu
if command -v qemu-system-arm >/dev/null && bin/zs build tests/mcu/effects.zs --target cortex-m0plus -o "$tmp/effects.elf" 2>"$tmp/effects.log" \
   && [ "$(timeout 60 qemu-system-arm -M microbit -nographic -semihosting-config enable=on,target=native -kernel "$tmp/effects.elf" 2>&1 | grep -v '^#zs')" = "$(cat tests/mcu/effects.expected)" ]; then
  echo "ok   tests/mcu/effects.zs (effect handlers on a Cortex-M0+, under qemu)"
else echo "FAIL tests/mcu/effects.zs"; cat "$tmp/effects.log"; fail=1; fi

# the library checks on its own (an editor opening one of its files must not see everything
# defined twice)
if bin/zs check --strict lib/core/Collections/List.zs >"$tmp/lib.log" 2>&1; then echo "ok   zs check lib (the library on its own)"
else echo "FAIL zs check lib"; head -5 "$tmp/lib.log"; fail=1; fi

# the library is fully documented, and docs/reference has its current pages, all in the index
tests/reference.sh "$tmp/ref" 2>&1
if grep -q "_Undocumented._" "$tmp/ref"/*.md; then
  echo "FAIL undocumented library items:"; grep -B4 "_Undocumented._" "$tmp/ref"/*.md | grep '#'; fail=1
elif ! diff -rq -x README.md "$tmp/ref" docs/reference >/dev/null; then
  echo "FAIL docs/reference is out of date (run: tests/reference.sh)"; diff -rq -x README.md "$tmp/ref" docs/reference; fail=1
elif missing=$(for p in "$tmp/ref"/*.md; do grep -q "($(basename "$p"))" docs/reference/README.md || basename "$p"; done) && [ -n "$missing" ]; then
  echo "FAIL docs/reference/README.md doesn't link: $missing"; fail=1
else echo "ok   library documented; docs/reference current"; fi

# the repository's own Z# code is formatted (zs fmt); the tests of parse errors don't parse, so
# they have no layout to check
unparsed='tests/err_and.zs|tests/err_operator_builtin.zs|tests/newcomer/(try_with|class|mutable_field|increment|return_braces).zs'
formatted=$(find tests lib packages -name '*.zs' | grep -Ev "^($unparsed)\$")
if bin/zs fmt --check $formatted 2>"$tmp/fmt.log"; then echo "ok   zs fmt --check"
else echo "FAIL zs fmt --check (run: bin/zs fmt \$(find tests lib packages -name '*.zs'))"; cat "$tmp/fmt.log"; fail=1; fi
# the syntax tree is lossless: every file's text comes back from it (0019)
if out=$(tests/cst/roundtrip.sh 2>&1); then echo "ok   tests/cst/roundtrip.sh ($out)"
else echo "FAIL tests/cst/roundtrip.sh"; echo "$out" | head; fail=1; fi
# zs fmt reflows lines over 100 columns on the tree, keeping comments (--stdin, as editors pipe)
if diff <(bin/zs fmt --stdin < tests/fmt/reflow.in 2>&1) tests/fmt/reflow.zs >"$tmp/reflow.diff"; then echo "ok   tests/fmt/reflow (zs fmt --stdin)"
else echo "FAIL tests/fmt/reflow"; cat "$tmp/reflow.diff"; fail=1; fi

# the language server: a scripted session (tests/lsp/session.sh) against its expected transcript
actual=$(tests/lsp/session.sh bin/zs 2>&1); expected=$(cat tests/lsp/session.out)
if [ "$actual" == "$expected" ]; then echo "ok   tests/lsp/session.sh"
else echo "FAIL tests/lsp/session.sh"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi

# the language server with two documents open, one using the other: a change to one publishes
# the other's diagnostics again (tests/lsp/modules.sh)
if diff <(tests/lsp/modules.sh bin/zs 2>&1) tests/lsp/modules.out >"$tmp/lspm.diff"; then echo "ok   tests/lsp/modules.sh"
else echo "FAIL tests/lsp/modules.sh"; cat "$tmp/lspm.diff"; fail=1; fi
# every mistake of a declaration, the same from zs check and the language server (tests/lsp/many.sh)
if diff <(tests/lsp/many.sh bin/zs 2>&1) tests/lsp/many.out >"$tmp/lspmany.diff"; then echo "ok   tests/lsp/many.sh"
else echo "FAIL tests/lsp/many.sh"; cat "$tmp/lspmany.diff"; fail=1; fi
# the language server on effects: rows in hover, the effects inlay hint, an operation's
# definition and references (tests/lsp/effects.sh)
if diff <(tests/lsp/effects.sh bin/zs 2>&1) tests/lsp/effects.expected >"$tmp/lspe.diff"; then echo "ok   tests/lsp/effects.sh"
else echo "FAIL tests/lsp/effects.sh"; cat "$tmp/lspe.diff"; fail=1; fi
# editing through the server (0019): renaming a record field across modules, signature help,
# code actions (tests/lsp/edits.sh)
if diff <(tests/lsp/edits.sh bin/zs 2>&1) tests/lsp/edits.expected >"$tmp/lspx.diff"; then echo "ok   tests/lsp/edits.sh"
else echo "FAIL tests/lsp/edits.sh"; cat "$tmp/lspx.diff"; fail=1; fi
# the build server: the binary an in-process build makes, errors and exit codes back
if diff <(tests/server.sh 2>&1) tests/server.expected >"$tmp/server.diff"; then echo "ok   tests/server.sh (the build server)"
else echo "FAIL tests/server.sh"; cat "$tmp/server.diff"; fail=1; fi

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
# Zed builds the grammar from the commit pinned in extension.toml: it must match the grammar here
pinned=$(grep -o '^rev = "[0-9a-f]*"' editors/zed/extension.toml | grep -o '[0-9a-f]\{40\}')
if git diff --quiet "$pinned" -- editors/tree-sitter-zsharp/grammar.js editors/tree-sitter-zsharp/src/scanner.c 2>/dev/null; then echo "ok   editors/zed pins the current grammar"
else echo "FAIL editors/zed/extension.toml pins an old grammar: commit the grammar, then set rev to that commit"; fail=1; fi
if command -v tree-sitter >/dev/null; then
  ts=$(editors/tree-sitter-zsharp/script/errors.sh 2>&1)
  if [ "$(echo "$ts" | tail -1)" = "files with errors: 0" ] && (cd editors/tree-sitter-zsharp && timeout 60 tree-sitter test >/dev/null 2>&1); then
    echo "ok   editors/tree-sitter-zsharp"
  else echo "FAIL editors/tree-sitter-zsharp"; echo "$ts" | tail -20; fail=1; fi
else echo "skip editors/tree-sitter-zsharp (no tree-sitter CLI; rebuild the dev image)"; fi

fi

# C interop: a directory with main.c links the static library built from its lib.zs
cc=(clang); [ -n "$target" ] && cc=(zig cc -target "$target")
[ $windows = 1 ] && [ -z "$target" ] && cc=(zig cc -target "$(uname -m | sed 's/arm64/aarch64/')-windows-gnu")
for c in $(find tests -name main.c | sort); do
  d=$(dirname "$c")
  if bin/zs build "$d/lib.zs" "${tgt[@]}" --lib -o "$tmp/lib.a" 2>"$tmp/build.log" && "${cc[@]}" -I"$tmp" "$c" "$tmp/lib.a" -lm "${syslibs[@]}" -o "$tmp/cexe" 2>>"$tmp/build.log"; then
    run=("${qemu[@]}" "$tmp/cexe"); [ $buildonly = 1 ] && run=(cat "$d/main.out"); [ $valgrind = 1 ] && run=(valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99 "$tmp/cexe")
    # a C program's stdout is in text mode on Windows: \n is written \r\n there
    actual=$("${run[@]}" 2>&1); code=$?; actual=${actual//$'\r'/}; [ $code = 99 ] && actual="$actual
(valgrind reported memory errors or leaks)"
  else actual=$(cat "$tmp/build.log"); fi
  expected=$(cat "$d/main.out")
  if [ "$actual" == "$expected" ]; then echo "ok   $c"
  else echo "FAIL $c"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi
done
# a C host's threads (host only): a Share value's handle used on 16 threads at once races on
# nothing under Helgrind, and a ref's handle released on another thread panics with its type
if [ -z "$target" ]; then
  ct="$tmp/ct"; mkdir -p "$ct"
  if bin/zs build tests/cthreads/lib.zs --lib -o "$ct/lib.a" 2>"$ct/log" && clang -I"$ct" tests/cthreads/main.c "$ct/lib.a" -lm -o "$ct/exe" 2>>"$ct/log"; then
    if valgrind --tool=helgrind -q --error-exitcode=99 "$ct/exe" >"$ct/out" 2>"$ct/hg"; then echo "ok   tests/cthreads under Helgrind"
    else echo "FAIL tests/cthreads under Helgrind"; head -30 "$ct/hg"; fail=1; fi
    actual=$("$ct/exe" other-thread 2>&1); code=$?
    expected="16 threads using a list's handle: every sum right
the counter on its own thread: 5
panic: zs_release: a handle of ref<int> used from another thread (make its type Share, or use it on the thread that made it)"
    if [ $code = 134 ] && [ "$actual" == "$expected" ]; then echo "ok   tests/cthreads: a handle used on another thread panics"
    else echo "FAIL tests/cthreads: a handle used on another thread (exit $code)"; diff <(echo "$expected") <(echo "$actual"); fail=1; fi
  else echo "FAIL tests/cthreads"; cat "$ct/log"; fail=1; fi
fi

# shared libraries (host only): a C program links the library as a .so, and a C shared library
# links a --lib archive whole (--whole-archive, so the archive needs position-independent code)
# with a C program calling Z# through it (POSIX's: a Windows DLL is another test)
if [ -z "$target" ] && [ $windows = 0 ]; then
  so="$tmp/so"; mkdir -p "$so"; run=(); [ $valgrind = 1 ] && run=(valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99)
  for kind in so whole; do
    if [ $kind = so ]; then
      built=$(bin/zs build tests/cexport/lib.zs --lib -o "$so/lib.so" 2>&1 && clang -I"$so" tests/cexport/main.c "$so/lib.so" -Wl,-rpath,"$so" -o "$so/exe" 2>&1)
    else
      built=$(bin/zs build tests/cexport/lib.zs --lib -o "$so/lib.a" 2>&1 \
        && clang -shared -I"$so" tests/cexport/host.c -Wl,--whole-archive "$so/lib.a" -Wl,--no-whole-archive -lm -o "$so/libhost.so" 2>&1 \
        && clang -I"$so" tests/cexport/main.c -L"$so" -lhost -Wl,-rpath,"$so" -o "$so/exe" 2>&1)
    fi
    if [ $? = 0 ]; then actual=$("${run[@]}" "$so/exe" 2>&1); [ $? = 99 ] && actual="$actual
(valgrind reported memory errors or leaks)"; else actual=$built; fi
    what="tests/cexport/main.c linking the library as a .so"; [ $kind = whole ] && what="tests/cexport/main.c through a C .so holding the --lib archive whole"
    if [ "$actual" == "$(cat tests/cexport/main.out)" ]; then echo "ok   $what"
    else echo "FAIL $what"; diff tests/cexport/main.out <(echo "$actual") | head -20; fail=1; fi
  done
fi

# ZS_STATS=1 (0020, decision 75): a unique array of trees through Array.Parallel.map moves each
# tree to its thread, so no object is marked shared
if [ -z "$target" ]; then
  if bin/zs build tests/stats/parallel_unique.zs -o "$tmp/pu" 2>"$tmp/pu.log" \
     && [ "$(ZS_STATS=1 "$tmp/pu" 2>&1 >/dev/null | grep -o '[0-9]* objects marked shared')" = "0 objects marked shared" ]; then
    echo "ok   tests/stats/parallel_unique.zs (nothing marked shared)"
  else echo "FAIL tests/stats/parallel_unique.zs"; cat "$tmp/pu.log"; ZS_STATS=1 "$tmp/pu" 2>&1 | tail -2; fail=1; fi
fi

# the bootstrap (0020): the compiler builds itself to the same bytes
if [ -z "$target" ]; then
  if out=$(tests/bootstrap.sh bin/zs 2>&1); then echo "ok   tests/bootstrap.sh ($(echo "$out" | paste -sd ';' | sed 's/;/; /g'))"
  else echo "FAIL tests/bootstrap.sh"; echo "$out"; fail=1; fi
fi
exit $fail
