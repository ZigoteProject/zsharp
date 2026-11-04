#!/usr/bin/env bash
# zs fuzz (0010, step 5): a property over bytes run under libFuzzer, which finds the planted bug
# (a header "ZS!" whose length byte sends a read past the input), guided by coverage; the crash's
# bytes are shrunk by replays to a smallest case, shown, and saved as the failure zs test replays
# first. libFuzzer's own chatter stays out of the output, and the flags after -- go to it.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/parse.zs" <<'ZS'
open Testing

// a packet: "ZS!", a length, the payload; the planted bug reads the payload's end from the
// length without checking the input holds it
let parse (input: array<u8>) : int =
  if Array.length input >= 4 && input.[0] = u8 90 && input.[1] = u8 83 && input.[2] = u8 33 then
    int input.[3 + int input.[3] + 1]
  else
    0

[<Tests>]
let tests =
  testList "parser" [
    testProperty "parses anything" (fun () ->
      prop {
        let! input = Gen.bytes ()
        let _ = parse input
        return true
      })
  ]
ZS
cd "$t"
export ZS_BACKTRACE=0
"$zs" fuzz parse.zs parses --for 60 2>/dev/null | sed -E 's/\([0-9]+ inputs in the corpus\)/(N inputs in the corpus)/; s/shrunk from [0-9]+ bytes to/shrunk from N bytes to/; s/in [0-9]+ runs/in N runs/; s/^fuzzing (.*) for 60 s \(corpus: .*\)$/fuzzing \1 (corpus kept)/'
echo "saved:"; (cd .zs-cache/failures && find . -type f | sed 's|^\./||')
echo "zs test replays it first:"; "$zs" test parse.zs 2>&1 | grep -v "^       panic\|^       index\|^       /" | head -4
echo "the flags after -- are libFuzzer's (-runs=0: the corpus is run, nothing new tried):"
"$zs" fuzz parse.zs parses --for 60 -- -runs=0 2>/dev/null | sed -E 's/; [0-9]+ inputs in the corpus/; N inputs in the corpus/; s/^fuzzing (.*) \(corpus: .*\)$/fuzzing \1 (corpus kept)/'
echo "and not those that start other processes:"; "$zs" fuzz parse.zs parses -- -jobs=2; echo "exit $?"
