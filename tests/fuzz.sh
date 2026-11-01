#!/usr/bin/env bash
# Programs broken at random: the tests' and examples' files cut short, a line dropped, doubled,
# moved or indented, a character dropped or a token put in. zs check and zs fmt --stdin take each
# one without crashing, panicking or hanging: a broken program is errors, never a compiler bug.
# Seeded, so a failure reproduces: ZS_FUZZ_SEED picks the programs (1 by default), ZS_FUZZ_COUNT
# how many (300).
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
seed=${ZS_FUZZ_SEED:-1}; count=${ZS_FUZZ_COUNT:-300}
RANDOM=$seed
mapfile -t files < <(find tests examples -name '*.zs' -size -24k | sort)
tokens=('(' ')' '[' ']' '{' '}' '[|' '|]' '|' '->' '<-' '|>' '=' ':' ',' ';' '.' '"' "'" '$"{' '}"' '"""'
  '(*' '*)' '//' '<' '>' '[<' '>]' 'let ' 'let rec ' 'in ' 'match ' 'with ' 'fun ' 'if ' 'then ' 'else '
  'type ' 'effect ' 'handle ' 'mutable ' 'for ' 'while ' 'do ' 'and ' 'of ' 'when ' 'as ' 'module '
  'open ' 'impl ' 'yield ' 'unsafe ' "'a " '0x' '1e' '-9223372036854775808' '\u{110000}' '_' '?')
# a number below n (n > 0) from two draws, so files past 32 KB are cut anywhere
below() { echo $(((RANDOM * 32768 + RANDOM) % $1)); }
# a broken copy of $1 in $t/Fuzz.zs, and what was done to it on standard output
mutate() {
  local f=$1 lines size k j
  lines=$(wc -l < "$f"); size=$(wc -c < "$f")
  [ "$lines" -gt 0 ] || lines=1
  k=$(($(below "$lines") + 1)); j=$(($(below "$lines") + 1))
  case $((RANDOM % 7)) in
    0) local cut; cut=$(below "$size"); head -c "$cut" "$f" > "$t/Fuzz.zs"; echo "cut at byte $cut" ;;
    1) sed "${k}d" "$f" > "$t/Fuzz.zs"; echo "line $k dropped" ;;
    2) sed "${k}p" "$f" > "$t/Fuzz.zs"; echo "line $k doubled" ;;
    3) awk -v k="$k" -v j="$j" 'NR == k { held = $0; next } { print } NR == j { print held }' "$f" > "$t/Fuzz.zs"
       echo "line $k moved after line $j" ;;
    4) sed "${k}s/^/ /" "$f" > "$t/Fuzz.zs"; echo "line $k indented one more" ;;
    5) local c=$((RANDOM % 80))
       awk -v k="$k" -v c="$c" 'NR == k { $0 = substr($0, 1, c) substr($0, c + 2) } { print }' "$f" > "$t/Fuzz.zs"
       echo "line $k: character $((c + 1)) dropped" ;;
    6) local c=$((RANDOM % 80)) tok=${tokens[RANDOM % ${#tokens[@]}]}
       TOK=$tok awk -v k="$k" -v c="$c" 'NR == k { $0 = substr($0, 1, c) ENVIRON["TOK"] substr($0, c + 1) } { print }' "$f" > "$t/Fuzz.zs"
       echo "line $k: '$tok' put in at column $((c + 1))" ;;
  esac
}
failed=0
# zs <what> exited <code>, with <log>: a crash (a signal), a panic or a hang is an exit status past
# 1, or a line saying panic (not one of a diagnostic's source lines, which quote the program)
verdict() {
  if [ "$2" -gt 1 ] || grep -v '^ *[0-9]* | ' "$3" | grep -q '^panic'; then
    failed=$((failed + 1))
    echo "seed $seed, program $i: zs $1 exit $2 on $f, $what"
    grep -v '^ *[0-9]* | ' "$3" | head -5
  fi
}
for i in $(seq "$count"); do
  f=${files[RANDOM % ${#files[@]}]}
  what=$(mutate "$f")
  timeout 60 bin/zs check "$t/Fuzz.zs" >"$t/check.log" 2>&1
  verdict check $? "$t/check.log"
  timeout 60 bin/zs fmt --stdin <"$t/Fuzz.zs" >/dev/null 2>"$t/fmt.log"
  verdict "fmt --stdin" $? "$t/fmt.log"
done
echo "$count broken programs, $failed compiler failures"
[ "$failed" = 0 ]
