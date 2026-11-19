#!/usr/bin/env bash
# The sanitizers check the code Z# compiles as well as the runtime's: every function has the
# sanitizer's attribute, without which its pass checks none of a function's loads and stores.
# Under --sanitize a write past a block in unsafe code is reported, and a unit held at an object's
# end (an access of no bytes, which AddressSanitizer checks as a byte at its address) isn't, nor
# a record or a tuple of units there.
# ThreadSanitizer's half is tests/ztest/tsan.sh.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t"
cat > past.zs <<'ZS'
// a write one byte past a block of one
let main () =
  let p: ptr<u8> = unsafe (Ptr.alloc 1)
  unsafe (Ptr.write (Ptr.add p 1) (u8 7))
  unsafe (Ptr.free p)
ZS
cat > units.zs <<'ZS'
// units held in objects, each at the object's end: a unit, a record of units, a tuple of units
type Box = { n: int; mark: unit }

type Marks = { a: unit; b: unit }

let main () =
  let r = ref ()
  r.Value <- ()
  let boxes = Array.init 3 (fun i -> ref { n = i; mark = () })
  boxes.[1].Value <- { n = 5; mark = r.Value }
  let units = Array.create 4 ()
  let t = Task.run (task { return () })
  let some = [ Some (); None; Some t ]
  let marks = ref { a = (); b = () }
  marks.Value <- { a = (); b = () }
  let pair = ref ((), ())
  pair.Value <- ((), ())
  println $"{boxes.[1].Value.n} {Array.length units} {List.length some} {r.Value = ()} {marks.Value.a = ()} {fst pair.Value = ()}"
ZS
"$zs" build past.zs -o past --sanitize && echo "a write past a block: $(ASAN_OPTIONS=exitcode=99 ./past 2>&1 | grep -o -m1 heap-buffer-overflow)"
"$zs" build units.zs -o units --sanitize && echo "units at objects' ends: $(ASAN_OPTIONS=exitcode=99:detect_leaks=1 ./units 2>&1)"
