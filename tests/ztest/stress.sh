#!/usr/bin/env bash
# zs test --stress (0009, D4): the tests at random on every core, over and over for the time
# given, each in its own process: a failure one run doesn't show (here, every fifth run of one
# test fails, and every seventh of another leaks, counted in a file) is found, each failing test
# shown once; ZS_LEAKCHECK=1 makes a leak at a test's exit a failure, in one run too.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/flaky.zs" <<'ZS'
open Testing

[<Cyclic>]
type Node = Node of next: ref<option<Node>>

// how many times this process's test ran before: a file the runs share
let count (name: string) =
  let path = IO.Path.combine (Environment.currentDirectory ()) (name + ".count")
  let n = match IO.File.readAllText path with | Ok s -> Option.defaultValue 0 (Int.parse (String.trim s)) | Error _ -> 0
  IO.File.writeAllText path (string (n + 1)) |> ignore
  n + 1

[<Tests>]
let tests =
  testList "flaky" [
    test "fails every fifth run" (fun () -> assert (count "fifth" % 5 <> 0))
    test "leaks every seventh run" (fun () ->
      if count "seventh" % 7 = 0 then
        let a = Node(ref None)
        let b = Node(ref (Some a))
        match a with
        | Node next -> next.Value <- Some b)
    test "always passes" (fun () -> assert (1 + 1 = 2))
  ]
ZS
cd "$t"
export ZS_LEAKCHECK=1
echo "one run:"
"$zs" test flaky.zs
echo "stress:"
"$zs" test flaky.zs --stress 4s | sed -E 's/^stress: [0-9]+ runs of 3 tests on [0-9]+ cores for 4 s, [1-9][0-9]* failed$/stress: runs of 3 tests, some failed/' | grep -v '^       \|^[1-9][0-9]* passed' | sort
