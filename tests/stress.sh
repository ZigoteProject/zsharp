#!/usr/bin/env bash
# Programs as big or as deep as generated code makes them, each built within a time limit and run:
# what was quadratic stays near linear, what recursed too deep for the compiler's stack compiles,
# and what is deeper still stops as a panic naming the overflow, not a bare SIGSEGV.
#   - a flat list literal and a flat array literal (each element's type variable bound to the one
#     before: unification followed the whole chain, without path compression)
#   - a chain of small functions, each calling the one before (inlining copied each one's inlined
#     body into the next, every one growing by the one before: quadratic, and as deep as long)
#   - long runs of statements, lets and else-ifs, and deeply nested parentheses; the else-ifs
#     built again, their Core read back from the cache as deep as it is
#   - a byte order mark and \r\n line ends
#   - text a million pieces long: a list printed, a string padded, a JSON string of escapes read
#     and written (each was a string added to at every piece: quadratic)
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# the program on standard input, built as $1 and run (each within a time limit): its last line
case_() {
  name=$1
  cat > "$t/$name.zs"
  if timeout 120 bin/zs build "$t/$name.zs" -o "$t/$name" >"$t/$name.log" 2>&1; then
    echo "$name: $(timeout 120 "$t/$name" | tail -1)"
  else
    echo "$name: build failed ($?)"; grep -v '^ *[0-9]* | ' "$t/$name.log" | head -3
  fi
}
items() { seq 0 $(($1 - 1)) | paste -sd ';' -; }

{ echo 'let main () ='; echo "  let x = [ $(items 20000) ]"; echo '  println $"{List.length x} {List.sum x}"'; echo '  0'; } | case_ list
{ echo 'let main () ='; echo "  let x = [| $(items 50000) |]"; echo '  println $"{Array.length x} {Array.sum x}"'; echo '  0'; } | case_ array
{ echo 'let f0 x = x'; for i in $(seq 1 1999); do echo "let f$i x = f$((i - 1)) x + 1"; done
  echo 'let main () ='; echo '  println $"{f1999 1}"'; echo '  0'; } | case_ chain
{ echo 'let main () ='; seq 0 4999 | sed 's/.*/  println "&"/'; echo '  0'; } | case_ statements
{ echo 'let main () ='; seq 0 4999 | sed 's/.*/  let a& = &/'; echo '  println $"{a0 + a4999}"'; echo '  0'; } | case_ lets
{ echo 'let main () ='; echo '  let x = 4321'
  printf '  let y = '; for i in $(seq 0 4999); do printf 'if x = %d then %d else ' $i $((i * 2)); done; echo '0'
  echo '  println $"{y}"'; echo '  0'; } | case_ else-ifs
if timeout 120 bin/zs build "$t/else-ifs.zs" -o "$t/again" >"$t/again.log" 2>&1; then echo "else-ifs again: $(timeout 120 "$t/again" | tail -1)"
else echo "else-ifs again: build failed"; grep -v '^ *[0-9]* | ' "$t/again.log" | head -3; fi
{ echo 'let main () ='; printf '  let x = '; printf '(%.0s' $(seq 10000); printf 1; printf ')%.0s' $(seq 10000); echo
  echo '  println $"{x}"'; echo '  0'; } | case_ parentheses
printf '\xef\xbb\xbflet main () =\r\n  println "a byte order mark"\r\n  0\r\n' | case_ bom
{ echo 'let main () ='; echo '  let shown = string (List.init 1000000 id)'; echo '  let wide = String.padLeft 4000000 "x"'
  echo '  match Json.parse ("\"" + String.repeat 2000000 "\\n" + "\"") with'
  echo '  | Ok (JString s) -> println $"{String.length shown} {String.length wide} {String.length s} {String.length (Json.print (JString s))}"'
  echo '  | _ -> println "not a string"'; echo '  0'; } | case_ texts

# zs fmt on 300 declarations over the width: each one's break after `=` taken, its list's refused
# (the string alone is too long), each line tried once and not again after every break below it
for i in $(seq 300); do echo "let m$i = String.concat [ \"$(printf 'x%.0s' $(seq 95))\"; \"y\" ]"; done > "$t/wide.zs"
if timeout 60 bin/zs fmt --stdin < "$t/wide.zs" > "$t/wide.out" 2>&1; then echo "fmt wide: $(grep -c '^  String.concat' "$t/wide.out") lines broken"
else echo "fmt wide: failed or too slow ($?)"; fi

# a statement failing after a long literal: the checker undoes what the statement bound, the
# literal's compressed chains of type variables included, and goes on with the next
{ echo 'let main () ='; echo "  let xs = [ $(items 5000) ]"; echo '  let n: string = List.length xs'
  echo '  println $"{n} {List.length xs}"'; echo '  0'; } > "$t/undo.zs"
echo "undone: $(bin/zs check "$t/undo.zs" 2>&1 | grep -v '^ *[0-9]* | ' | sed 's|^.*/undo.zs:||' | paste -sd ';' -)"

# deeper than any stack: the compiler's own overflow is a panic that says so (exit 134)
{ echo 'let main () ='; printf '  let x = '; printf '(%.0s' $(seq 300000); printf 1; printf ')%.0s' $(seq 300000); echo
  echo '  0'; } > "$t/deep.zs"
timeout 120 bin/zs check "$t/deep.zs" >/dev/null 2>"$t/deep.log"
echo "too deep: exit $? $(grep -m1 '^panic' "$t/deep.log")"
