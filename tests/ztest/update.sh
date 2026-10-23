#!/usr/bin/env bash
# zs test --update (0009): a failing expect test's literal is rewritten in the source, through
# the lossless tree (a plain string when it fits, else a raw one on lines of its own), and the
# tests then pass.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/shapes.zs" <<'ZS'
open Testing

type Shape =
  | Circle of float
  | Rect of float * float

let lines (s: string) = String.splitLines s

[<Tests>]
let tests =
  testList "shapes" [
    test "a circle" (fun () -> expect (Circle 1.5) "Circle 2")
    test "lines" (fun () ->
      expect (lines "a\nb") "")
    test "text" (fun () -> expect "first\n  second" "")
  ]
ZS
cd "$t"
"$zs" test shapes.zs --update | grep -v "^       "
cat shapes.zs | sed -n '/\[<Tests>\]/,$p'
"$zs" test shapes.zs
