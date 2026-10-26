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
# the architecture the programs are built for: the target's, else this machine's
arch=$(uname -m); [ -n "$target" ] && arch=${target%%-*}
for t in $(find tests -name '*.zs' | sort); do
  base=${t%.zs}
  [ -f "$base.out" ] || [ -f "$base.err" ] || continue
  # base.host-only: the reason it can't run cross-compiled under qemu-user
  if [ -n "$target" ] && [ -f "$base.host-only" ]; then echo "skip $t ($(cat "$base.host-only"))"; continue; fi
  # base.x86_64-only: the reason it's about x86-64 (its CPU features, its intrinsics): skipped in a
  # build for another architecture, an arm64 machine's own included
  if [ -f "$base.x86_64-only" ] && [ "$arch" != x86_64 ]; then echo "skip $t ($(cat "$base.x86_64-only"))"; continue; fi
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

# the pool's one worker going to sleep as jobs are forked: woken for each one (a wake-up lost
# hangs it, with nothing polling the deques to find the job)
if bin/zs build --strict tests/parallel/wake.zs -o "$tmp/wake" 2>"$tmp/wake.log" \
   && [ "$(ZS_WORKERS=2 timeout 120 "$tmp/wake" 2>&1)" = "$(cat tests/parallel/wake.expected)" ]; then echo "ok   tests/parallel/wake.zs (one worker, woken for every job)"
else echo "FAIL tests/parallel/wake.zs"; cat "$tmp/wake.log"; fail=1; fi

# aarch64's intrinsics (Simd.Arm): built for it and run under qemu
if command -v qemu-aarch64 >/dev/null && bin/zs build tests/simd/arm.zs --target aarch64-linux-musl -o "$tmp/arm" 2>"$tmp/arm.log" \
   && [ "$(qemu-aarch64 "$tmp/arm" 2>&1)" = "$(cat tests/simd/arm.expected)" ]; then echo "ok   tests/simd/arm.zs (built for aarch64, under qemu)"
else echo "FAIL tests/simd/arm.zs"; cat "$tmp/arm.log"; fail=1; fi

# a 32-bit Arm Linux build has 32-bit words, as its runtime does (0027)
if bin/zs build examples/simple.zs --target arm-linux-musleabihf --emit-llvm -o "$tmp/armlinux" 2>"$tmp/armlinux.log" \
   && grep -q '@zs_alloc(i32)' "$tmp/armlinux.ll"; then echo "ok   examples/simple.zs for arm-linux-musleabihf (32-bit words)"
else echo "FAIL examples/simple.zs for arm-linux-musleabihf"; cat "$tmp/armlinux.log"; fail=1; fi

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

# layout facts on a 32-bit chip: sizeof<int> is the 32-bit word there (0004), under qemu
if command -v qemu-system-arm >/dev/null && bin/zs build tests/mcu/layout.zs --target cortex-m4 -o "$tmp/layout.elf" 2>"$tmp/layout.log" \
   && [ "$(timeout 60 qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on,target=native -kernel "$tmp/layout.elf" 2>&1 | grep -v '^#zs')" = "$(cat tests/mcu/layout.expected)" ]; then
  echo "ok   tests/mcu/layout.zs (layout facts on a Cortex-M4, under qemu)"
else echo "FAIL tests/mcu/layout.zs"; cat "$tmp/layout.log"; fail=1; fi

# interrupt handlers (0012) on both chips under qemu: a pended line's handler counting in an
# Atomic and pushing to an Spsc, SysTick's handler with Runtime.ticks counting up; tasks on the
# runtime's loop (0016), freeing what they allocated (live=0 at exit); and what a handler can't
# be, with the board's lines
if command -v qemu-system-arm >/dev/null; then
  for chip in cortex-m4 cortex-m0plus; do
    board=$([ $chip = cortex-m4 ] && echo mps2-an386 || echo microbit)
    for t in isr systick cpu bits task; do
      if bin/zs build tests/mcu/$t.zs --target $chip -o "$tmp/$t.elf" 2>"$tmp/$t.log" \
         && out=$(timeout 60 qemu-system-arm -M $board -nographic -semihosting-config enable=on,target=native -kernel "$tmp/$t.elf" 2>&1) \
         && [ "$(echo "$out" | grep -v '^#zs')" = "$(cat tests/mcu/$t.expected)" ] \
         && { [ $t != task ] || echo "$out" | grep -q ' live=0 '; }; then
        echo "ok   tests/mcu/$t.zs on $chip (under qemu)"
      else echo "FAIL tests/mcu/$t.zs on $chip"; cat "$tmp/$t.log"; fail=1; fi
    done
  done
fi
# a real board (0027): the Nucleo-F401RE's firmware builds; an image for it (its STM32F401RE's
# flash and RAM, output over RTT) boots on qemu's STM32F405, which has the same memory map, and its
# output is read from its RAM, the RTT block found by its ID as a probe finds it (and by its
# symbol, as probe-rs does)
if bin/zs build examples/mcu/nucleo-f401.zs --target nucleo-f401 -Os -o "$tmp/nucleo.elf" 2>"$tmp/nucleo.log"; then echo "ok   examples/mcu/nucleo-f401.zs (builds for nucleo-f401)"
else echo "FAIL examples/mcu/nucleo-f401.zs"; cat "$tmp/nucleo.log"; fail=1; fi
if command -v qemu-system-arm >/dev/null && command -v node >/dev/null; then
  if bin/zs build tests/mcu/bits.zs --target nucleo-f401 -o "$tmp/bits.elf" 2>"$tmp/bits.log" \
     && llvm-nm "$tmp/bits.elf" | grep -q ' _SEGGER_RTT$' \
     && (sleep 2; echo "pmemsave 0x20000000 0x18000 \"$tmp/ram.bin\""; sleep 1; echo quit) | timeout 30 qemu-system-arm -M netduinoplus2 -display none -monitor stdio -serial null -kernel "$tmp/bits.elf" >/dev/null 2>&1 \
     && [ "$(node tests/mcu/rtt.mjs "$tmp/ram.bin" | grep -v '^#zs')" = "$(cat tests/mcu/bits.expected)" ]; then
    echo "ok   tests/mcu/bits.zs on nucleo-f401 (under qemu's STM32F405, output over RTT)"
  else echo "FAIL tests/mcu/bits.zs on nucleo-f401"; cat "$tmp/bits.log"; fail=1; fi
fi
# the flagship (phase 12): examples/nucleo, built by zs build alone (zs.toml's target), its shell
# tested on this computer, then run on qemu's STM32F405 (the same memory map and USART2): commands
# typed at USART2 reach the shell's task through its handler's Spsc and Signal, the replies come
# back, and the log is read over RTT from a dump of its RAM (the monitor's socket, then quit)
if (cd examples/nucleo && "$OLDPWD/bin/zs" build -Os -o "$tmp/flagship" >"$tmp/flagship.log" 2>&1 && "$OLDPWD/bin/zs" test >>"$tmp/flagship.log" 2>&1); then
  echo "ok   examples/nucleo (zs build for the board, zs test of its shell)"
else echo "FAIL examples/nucleo"; cat "$tmp/flagship.log"; fail=1; fi
if command -v qemu-system-arm >/dev/null && command -v node >/dev/null && command -v nc >/dev/null; then
  serial=$( (sleep 1; printf 'status\r'; sleep 0.3; printf 'blink 100\r'; sleep 0.3; printf 'reboot\r'; sleep 0.5
             printf 'pmemsave 0x20000000 0x18000 "%s"\nquit\n' "$tmp/flagship.ram" | nc -U "$tmp/mon.sock" >/dev/null) \
           | timeout 30 qemu-system-arm -M netduinoplus2 -display none -monitor "unix:$tmp/mon.sock,server,nowait" -serial null -serial stdio -kernel "$tmp/flagship" 2>/dev/null | tr -d '\r')
  if [ "$serial" = "$(printf '\n> status\nled off\n> blink 100\nled blinking every 100 ms\n> reboot\ncommands: on | off | blink <ms> | status\n> ')" ] \
     && [ "$(node tests/mcu/rtt.mjs "$tmp/flagship.ram")" = "$(printf 'nucleo: ready; USART2 at 115200 takes on | off | blink <ms> | status\nstatus: led off\nblink 100: led blinking every 100 ms\nreboot: commands: on | off | blink <ms> | status')" ]; then
    echo "ok   examples/nucleo under qemu's STM32F405 (its shell over USART2, its log over RTT)"
  else echo "FAIL examples/nucleo under qemu"; echo "$serial"; fail=1; fi
fi
# a driver's receive side as a task (0016): it waits for the UART's receive interrupt
# (Irq.wait); qemu's serial is fed once the program has turned its receiver on (input before
# that, qemu's UART refuses and never asks for again)
if command -v qemu-system-arm >/dev/null && bin/zs build examples/mcu/uart.zs --target cortex-m4 -o "$tmp/uart.elf" 2>"$tmp/uart.log" \
   && [ "$( (sleep 1; printf 'hello there\n') | timeout 60 qemu-system-arm -M mps2-an386 -nographic -semihosting-config enable=on,target=native -kernel "$tmp/uart.elf" 2>/dev/null)" = "$(printf 'Hello from a Z# UART driver: type a line\nhello there\nyou typed 11 bytes: hello there')" ]; then
  echo "ok   examples/mcu/uart.zs (a task waiting for the UART's interrupt, under qemu)"
else echo "FAIL examples/mcu/uart.zs"; cat "$tmp/uart.log"; fail=1; fi
for t in err_isr err_isr_share err_isr_heap err_critical_heap err_task_spawn; do
  if [ "$(bin/zs build --strict tests/mcu/$t.zs --target cortex-m4 -o "$tmp/err.elf" 2>&1 | grep -v '^ [ 0-9]* | ')" = "$(cat tests/mcu/$t.expected)" ]; then echo "ok   tests/mcu/$t.zs"
  else echo "FAIL tests/mcu/$t.zs"; fail=1; fi
done
# --no-heap (0012): an image with no heap (no zs_alloc in it) runs; a startup value that would
# allocate is an error naming it
if [ "$(bin/zs build --strict tests/mcu/err_noheap.zs --target cortex-m4 --no-heap -o "$tmp/err.elf" 2>&1 | grep -v '^ [ 0-9]* | ')" = "$(cat tests/mcu/err_noheap.expected)" ]; then echo "ok   tests/mcu/err_noheap.zs"
else echo "FAIL tests/mcu/err_noheap.zs"; fail=1; fi
if command -v qemu-system-arm >/dev/null && bin/zs build tests/mcu/noheap.zs --target cortex-m0plus --no-heap -o "$tmp/noheap.elf" 2>"$tmp/noheap.log" \
   && ! llvm-nm "$tmp/noheap.elf" | grep -q zs_alloc \
   && [ "$(timeout 60 qemu-system-arm -M microbit -nographic -semihosting-config enable=on,target=native -kernel "$tmp/noheap.elf" 2>&1 | grep -v '^#zs')" = "$(cat tests/mcu/noheap.expected)" ]; then
  echo "ok   tests/mcu/noheap.zs (--no-heap on a Cortex-M0+, under qemu)"
else echo "FAIL tests/mcu/noheap.zs"; cat "$tmp/noheap.log"; fail=1; fi

# Math where libm is compiler-rt's and the runtime's (pow, atan2, round: fdlibm's, checked against
# the host's libm by tests/libm.sh), with a host's results: both chips under qemu, and wasm32
if out=$(tests/libm.sh 2>&1); then echo "ok   tests/libm.sh (the runtime's pow, atan2 and round against the host's libm)"
else echo "FAIL tests/libm.sh"; echo "$out"; fail=1; fi
if command -v qemu-system-arm >/dev/null; then
  for chip in cortex-m4 cortex-m0plus; do
    board=$([ $chip = cortex-m4 ] && echo mps2-an386 || echo microbit)
    if bin/zs build tests/mcu/math.zs --target $chip -o "$tmp/math.elf" 2>"$tmp/math.log" \
       && [ "$(timeout 60 qemu-system-arm -M $board -nographic -semihosting-config enable=on,target=native -kernel "$tmp/math.elf" 2>&1 | grep -v '^#zs')" = "$(cat tests/mcu/math.expected)" ]; then
      echo "ok   tests/mcu/math.zs on $chip (under qemu)"
    else echo "FAIL tests/mcu/math.zs on $chip"; cat "$tmp/math.log"; fail=1; fi
  done
fi
if command -v node >/dev/null && bin/zs build tests/mcu/math.zs --target wasm32 -o "$tmp/math.wasm" 2>"$tmp/math.log" \
   && [ "$(node bin/run-wasm.mjs "$tmp/math.wasm" 2>&1)" = "$(cat tests/mcu/math.expected)" ]; then echo "ok   tests/mcu/math.zs on wasm32 (under node)"
elif command -v node >/dev/null; then echo "FAIL tests/mcu/math.zs on wasm32"; cat "$tmp/math.log"; fail=1; fi

# C interop on a chip, both ways, under qemu: Z# calling C with structs by value in every shape
# (AAPCS, hard and soft float), and a C firmware with its own startup calling a Z# library built
# with --lib (tests/cexport/bare.c, no C library), against the host's expected output
if command -v qemu-system-arm >/dev/null; then
  for chip in cortex-m4 cortex-m0plus; do
    case $chip in
      cortex-m4) board=mps2-an386; zt=thumb-freestanding-eabihf; zc=cortex_m4+vfp4d16sp ;;
      *) board=microbit; zt=thumb-freestanding-eabi; zc=cortex_m0plus ;;
    esac
    qsys=(timeout 60 qemu-system-arm -M $board -nographic -semihosting-config enable=on,target=native -kernel)
    if bin/zs build tests/cimport/abi.zs --target $chip -o "$tmp/abi.elf" 2>"$tmp/abi.log" \
       && [ "$("${qsys[@]}" "$tmp/abi.elf" 2>&1 | grep -v '^#zs')" = "$(cat tests/cimport/abi.out)" ]; then echo "ok   tests/cimport/abi.zs on $chip (under qemu)"
    else echo "FAIL tests/cimport/abi.zs on $chip"; cat "$tmp/abi.log"; fail=1; fi
    if bin/zs build tests/mcu/vendor/main.zs --target $chip -o "$tmp/vendor.elf" 2>"$tmp/vendor.log" \
       && [ "$("${qsys[@]}" "$tmp/vendor.elf" 2>&1 | grep -v '^#zs')" = "$(cat tests/mcu/vendor/main.expected)" ]; then echo "ok   tests/mcu/vendor/main.zs on $chip (import c of a header for the chip, under qemu)"
    else echo "FAIL tests/mcu/vendor/main.zs on $chip"; cat "$tmp/vendor.log"; fail=1; fi
    fw="$tmp/fw"; rm -rf "$fw"; mkdir -p "$fw"
    # the board's script with the shared Cortex-M layout in place of its INCLUDE
    awk -v b=runtime/boards/cortex-m.ld '/INCLUDE cortex-m.ld/ { while ((getline l < b) > 0) print l; next } { print }' "runtime/boards/$board.ld" > "$fw/fw.ld"
    if bin/zs build tests/cexport/lib.zs --lib --target $chip -o "$fw/lib.a" 2>"$fw/log" \
       && zig cc -target $zt -mcpu=$zc -O2 -ffunction-sections -fdata-sections -I"$fw" tests/cexport/bare.c "$fw/lib.a" -T"$fw/fw.ld" -Wl,--gc-sections -Wl,--entry=Reset_Handler -o "$fw/fw.elf" 2>>"$fw/log" \
       && [ "$("${qsys[@]}" "$fw/fw.elf" 2>&1)" = "$(cat tests/cexport/main.out)" ]; then echo "ok   tests/cexport/bare.c on $chip (a C firmware calling a Z# library, under qemu)"
    else echo "FAIL tests/cexport/bare.c on $chip"; cat "$fw/log"; fail=1; fi
  done
fi

# a project for a chip (tests/project/chip): zs run builds it for its zs.toml's target, with its
# [c.<target>] source and its [target.<name>] heap, and runs it under qemu
if command -v qemu-system-arm >/dev/null; then
  actual=$( (cd tests/project/chip && "$OLDPWD/bin/zs" run 2>&1 | grep -v '^#zs') )
  if [ "$actual" = "$(cat tests/project/chip/run.expected)" ]; then echo "ok   tests/project/chip (a project's target, its C for it and its heap)"
  else echo "FAIL tests/project/chip"; diff <(echo "$actual") tests/project/chip/run.expected; fail=1; fi
fi

# C interop on freestanding WebAssembly, both ways, under node: structs by value (its C ABI), and
# a C program linked with a Z# library archive (--lib -o lib.a), the runtime's _start running its
# main
if command -v node >/dev/null; then
  if bin/zs build tests/cimport/abi.zs --target wasm32 -o "$tmp/abi.wasm" 2>"$tmp/abi.log" \
     && [ "$(node bin/run-wasm.mjs "$tmp/abi.wasm" 2>&1)" = "$(cat tests/cimport/abi.out)" ]; then echo "ok   tests/cimport/abi.zs on wasm32 (under node)"
  else echo "FAIL tests/cimport/abi.zs on wasm32"; cat "$tmp/abi.log"; fail=1; fi
  wf="$tmp/wf"; rm -rf "$wf"; mkdir -p "$wf"
  if bin/zs build tests/cexport/lib.zs --lib --target wasm32 -o "$wf/lib.a" 2>"$wf/log" \
     && zig cc -target wasm32-freestanding -O2 -I"$wf" tests/cexport/bare.c "$wf/lib.a" -o "$wf/prog.wasm" 2>>"$wf/log" \
     && [ "$(node bin/run-wasm.mjs "$wf/prog.wasm" 2>&1)" = "$(cat tests/cexport/main.out)" ]; then echo "ok   tests/cexport/bare.c on wasm32 (a C program calling a Z# library, under node)"
  else echo "FAIL tests/cexport/bare.c on wasm32"; cat "$wf/log"; fail=1; fi
fi

# freestanding WebAssembly: the same effects test, run by the Node host
if command -v node >/dev/null && bin/zs build tests/mcu/effects.zs --target wasm32 -o "$tmp/effects.wasm" 2>"$tmp/effects.log" \
   && [ "$(node bin/run-wasm.mjs "$tmp/effects.wasm" 2>&1)" = "$(cat tests/mcu/effects.expected)" ]; then
  echo "ok   tests/mcu/effects.zs (effect handlers on wasm32, under node)"
else echo "FAIL tests/mcu/effects.zs (wasm32)"; cat "$tmp/effects.log"; fail=1; fi

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

# type names written in annotations: their hover (declaration and doc), references and
# definition; and a function's signature at the end of its line (tests/lsp/types.sh)
lspt=$(tests/lsp/types.sh bin/zs 2>&1)
if echo "$lspt" | grep -q 'type Point = { x: int; y: int }\\n\\u0060\\u0060\\u0060\\n\\nA point on the plane' \
   && [ "$(echo "$lspt" | grep '"id":3' | grep -o '"uri"' | wc -l)" -eq 4 ] \
   && echo "$lspt" | grep -q '"id":4,"result":{"uri":"[^"]*types.zs","range":{"start":{"line":2,"character":5}' \
   && echo "$lspt" | grep -q 'type option\\u003C' && echo "$lspt" | grep -q '"label":"// Point -\\u003E int -\\u003E Point"' \
   && echo "$lspt" | grep '"id":8' | grep -q '6 bytes, aligned to 2'; then
  echo "ok   tests/lsp/types.sh"
else echo "FAIL tests/lsp/types.sh"; echo "$lspt" | cut -c1-300; fail=1; fi

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
# the VS Code (and Rider) TextMate grammar highlights the tree-sitter highlights' keywords
ts_kw=$(awk '/^\[$/{k=1;s="";next} k&&/^\] @keyword/{print s;k=0} k{s=s" "$0}' editors/tree-sitter-zsharp/queries/highlights.scm | grep -o '"[a-z]*"' | tr -d '"' | sort -u)
tm_kw=$(grep -o '\\\\b(?:let|rec[a-z|]*' editors/vscode/syntaxes/zsharp.tmLanguage.json | sed 's/.*(?://' | tr '|' '\n' | sort -u)
if [ -n "$ts_kw" ] && [ "$ts_kw" = "$tm_kw" ]; then echo "ok   editors/vscode keywords"
else echo "FAIL editors/vscode/syntaxes keywords differ from the tree-sitter highlights'"; diff <(echo "$ts_kw") <(echo "$tm_kw"); fail=1; fi
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
