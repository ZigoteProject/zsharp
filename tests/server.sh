#!/usr/bin/env bash
# The build server: zs build asks it when it runs, and starts one when none does. A build it
# answers is the binary an in-process build makes, its errors and exit code come back, and
# zs server stop ends it.
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'bin/zs server stop >/dev/null 2>&1; rm -rf "$t"' EXIT
export XDG_CACHE_HOME=$t/cache
unset ZS_NO_SERVER
# binaries compared have one name, each in a directory of its own: macOS's ad-hoc signature holds
# the binary's name
mkdir -p "$t/a" "$t/b" "$t/c"
bin/zs build tests/spans.zs -o "$t/a/exe" # none yet: built here, and one started
for i in $(seq 100); do ls "$t"/cache/zs/servers/*.sock >/dev/null 2>&1 && break; sleep 0.1; done
# whoever reaches the socket runs zs commands as this user: its directory is private, whatever the
# umask it was made under (stat -c is GNU's, stat -f BSD's, macOS's)
servers=$t/cache/zs/servers
echo "its directory: $(stat -c %a "$servers" 2>/dev/null || stat -f %OLp "$servers")"
bin/zs build tests/spans.zs -o "$t/b/exe" --time 2>"$t/time"
grep -q "^total (build server)" "$t/time" && echo "the server built it"
ZS_NO_SERVER=1 XDG_CACHE_HOME=$t/ref bin/zs build tests/spans.zs -o "$t/c/exe"
cmp -s "$t/a/exe" "$t/b/exe" && cmp -s "$t/b/exe" "$t/c/exe" && echo "the same binary as built in-process"
bin/zs build tests/err_yield.zs -o "$t/q" 2>"$t/err"
echo "an error: exit $?, $(head -1 "$t/err")"
# a build the server runs that builds a package's provider (zs build, as a process) has it built
# in that process: asked of the server, busy with this very build, it would wait for ever
root=$PWD
mkdir -p "$t/p/pkg" "$t/p/shout"
cp tests/providers/pkg/zs.toml tests/providers/pkg/main.zs tests/providers/pkg/words.txt "$t/p/pkg/"
cp tests/providers/shout/zs.toml tests/providers/shout/Main.zs "$t/p/shout/"
(cd "$t/p/pkg" && timeout 300 "$root/bin/zs" build main.zs -o "$t/p/exe" --time 2>"$t/ptime")
code=$?
echo "a package's provider under the server: exit $code, served $(grep -c '^total (build server)' "$t/ptime"), $("$t/p/exe")"
# a client that connects and sends nothing holds up no build after it: it's dropped in seconds
cat > "$t/stall.zs" <<'ZS'
let main () =
  match Environment.args () with
  | [ path ] ->
    Task.run (
      task {
        let! got = Unix.connect path
        match got with
        | Ok s ->
          use c = s
          do! Task.sleep 20000
          return 0
        | Error _ -> return 1
      })
  | _ -> 2
ZS
ZS_NO_SERVER=1 bin/zs build "$t/stall.zs" -o "$t/stall" >"$t/stall.log" 2>&1
"$t/stall" "$(ls "$t"/cache/zs/servers/*.sock | head -1)" &
stall=$!
sleep 0.5
mkdir -p "$t/d"
timeout 15 bin/zs build tests/spans.zs -o "$t/d/exe"
echo "a build after a client that sends nothing: exit $?"
kill "$stall" 2>/dev/null; wait "$stall" 2>/dev/null
# two servers started together can both find none: the second's listen takes the path (here a
# rename stands for its unlink), and the first, stopped, must leave the second's socket alone
cat > "$t/poke.zs" <<'ZS'
let main () =
  match Environment.args () with
  | [ path; word ] ->
    Task.run (
      task {
        let! got = Unix.connect path
        match got with
        | Ok s ->
          use c = s
          let body = String.ofByte (u8 0) + word
          let! sent = Tcp.writeText c $"{String.length body}\n{body}"
          if Result.isOk sent then
            return 0
          else
            return 1
        | Error _ -> return 1
      })
  | _ -> 2
ZS
ZS_NO_SERVER=1 bin/zs build "$t/poke.zs" -o "$t/poke" >"$t/poke.log" 2>&1
mkdir -p "$t/race"
race=$t/race/s.sock
bin/zs server "$race" >/dev/null 2>&1 &
first=$!
for i in $(seq 100); do [ -S "$race" ] && break; sleep 0.1; done
mv "$race" "$race.first"
bin/zs server "$race" >/dev/null 2>&1 &
second=$!
for i in $(seq 100); do [ -S "$race" ] && break; sleep 0.1; done
"$t/poke" "$race.first" stop || kill "$first"; wait "$first"
echo "two servers on one path, the first stopped: the second's socket $([ -S "$race" ] && echo kept || echo deleted)"
"$t/poke" "$race" stop || kill "$second"; wait "$second"
echo "the second stopped: its own socket $([ -S "$race" ] && echo kept || echo deleted)"
bin/zs server stop
sleep 0.5
echo "stopped: $(ls "$servers" 2>/dev/null | wc -l | tr -d ' ') sockets left" # (tr: BSD's wc, macOS's, pads its count)
