#!/usr/bin/env bash
# zs provide (0001, track P's first step): the json and csv providers' modules printed from the
# samples here, the errors for what isn't a provider, an option or a file, and main.zs built
# with the two modules beside it (as a project keeps them in place of an import) and run
zs=$(realpath "${1:-bin/zs}"); dir=$(mktemp -d)
# $dir as zs names it: on Windows, Git Bash hands a native program /tmp/… as C:/…/Temp/…
at=$dir; command -v cygpath >/dev/null && at=$(cygpath -m "$dir")
cd "$(dirname "$0")"
"$zs" provide --list
echo "--- json"
"$zs" provide json weather.json | tee "$dir/Weather.zs"
echo "--- csv"
"$zs" provide csv stocks.csv --separator=';' | tee "$dir/Stocks.zs"
echo "--- sql"
"$zs" provide sql schema.sql | tee "$dir/Db.zs"
echo "--- sql with named queries (one query's module)"
"$zs" provide sql schema.sql --queries=queries.sql | sed -n '/^module OrdersFor/,/^$/p'
"$zs" provide sql schema.sql --queries=nowhere.sql; echo "exit $?"
printf -- '-- name: Bad :one\nSELECT nope FROM users;\n' > "$dir/bad.sql"; "$zs" provide sql schema.sql --queries="$dir/bad.sql" 2>&1 | sed "s|$at/||"; echo "exit ${PIPESTATUS[0]}"
echo "--- svd (GPIOA only; the module's head and one register)"
# (tr: BSD's wc, macOS's, pads its count)
"$zs" provide svd ../../examples/mcu/stm32f401-part.svd --only=GPIOA > "$dir/Gpio.zs"; echo "exit $?, $(wc -l < "$dir/Gpio.zs" | tr -d ' ') lines"
sed -n '1,8p' "$dir/Gpio.zs"; grep -n -A12 'type Bsrr' "$dir/Gpio.zs" | grep -E 'Bsrr|bs5|br15|read|write|modify' | head -8
echo "--- c: a header's declarations as Z#"
"$zs" provide c cshapes/shapes.h
echo "--- a provider on PATH: zs-provider-upper, a Z# program"
# a program, since Windows starts no script as one; named .exe there, as its programs are
mkdir -p "$dir/bin"; exe=""; case $(uname -s) in MINGW* | MSYS* | CYGWIN*) exe=.exe ;; esac
cat > "$dir/upper.zs" <<'ZS'
// a word per line in the file, as a constant: --prefix= names the constants
let main () =
  match Environment.args () with
  | [] ->
    eprintln "usage: zs-provider-upper <file> [--prefix=<prefix>]"
    1
  | file :: opts ->
    let prefixOf (a: string) =
      if String.startsWith "--prefix=" a then Some(String.sub a 9 (String.length a - 9)) else None
    match List.tryFind (fun (a: string) -> Option.isNone (prefixOf a)) opts with
    | Some a ->
      eprintln $"unknown option '{a}' (prefix)"
      1
    | None ->
      match File.readAllLines file with
      | Error _ ->
        eprintln $"{file} not found"
        1
      | Ok words ->
        let prefix = Option.defaultValue "" (List.tryPick prefixOf (List.rev opts))
        println $"// provided by upper 1.0 from {file}\n// input: {file}\n"
        for w in words do
          if w <> "" then
            println $"let {prefix}{w} = \"{String.toUpper w}\""
        0
ZS
ZS_NO_SERVER=1 "$zs" build --strict "$dir/upper.zs" -o "$dir/bin/zs-provider-upper$exe"
printf 'alpha\nbeta\n' > words.txt
PATH="$dir/bin:$PATH" "$zs" provide --list | tail -1
PATH="$dir/bin:$PATH" "$zs" provide upper words.txt --prefix=w_
PATH="$dir/bin:$PATH" "$zs" provide upper words.txt --prefx=w_; echo "exit $?"
printf 'import upper ("words.txt", prefix = "w_")\n\nlet main () =\n  println $"{w_alpha} {w_beta}"\n  0\n' > upper_use.zs
PATH="$dir/bin:$PATH" ZS_NO_SERVER=1 "$zs" build --strict upper_use.zs -o "$dir/upper_use" && "$dir/upper_use"
echo "--- the same build with the provider gone from PATH: the cached module, with a warning"
ZS_NO_SERVER=1 "$zs" build upper_use.zs -o "$dir/upper_use2" 2>&1 | grep -v '^ [ 0-9]* | '; "$dir/upper_use2"
printf 'alpha\nbeta\ngamma\n' > words.txt
ZS_NO_SERVER=1 "$zs" build upper_use.zs -o "$dir/upper_use3" 2>&1 | grep -v '^ [ 0-9]* | '; "$dir/upper_use3"
rm -rf words.txt upper_use.zs .zs-cache/providers/upper_use
echo "--- errors (exit codes)"
"$zs" provide jsn weather.json; echo "exit $?"
"$zs" provide csv stocks.csv --seperator=';'; echo "exit $?"
"$zs" provide csv stocks.csv --types=volume:money; echo "exit $?"
"$zs" provide svd ../../examples/mcu/stm32f401-part.svd --only=GPIOA,SPI9; echo "exit $?"
printf 'CREATE TABLE empty ();\n' > "$dir/bad.sql"; "$zs" provide sql "$dir/bad.sql" 2>&1 | sed "s|$at/||"; echo "exit ${PIPESTATUS[0]}"
printf '<device><name>x</name><peripherals><peripheral><name>A</name></peripheral>\n' > "$dir/bad.svd"; "$zs" provide svd "$dir/bad.svd" 2>&1 | sed "s|$at/||"; echo "exit ${PIPESTATUS[0]}"
"$zs" provide json nowhere.json; echo "exit $?"
echo '{"a": [1, 2' > "$dir/broken.json"; "$zs" provide json "$dir/broken.json" 2>&1 | sed "s|$at/||"; echo "exit ${PIPESTATUS[0]}"
printf 'a;b\n1;2;3\n' > "$dir/wide.csv"; "$zs" provide csv "$dir/wide.csv" --separator=';' 2>&1 | sed "s|$at/||"; echo "exit ${PIPESTATUS[0]}"
"$zs" provide; echo "exit $?"
echo "--- options"
"$zs" provide json weather.json --root=Weather --types=humidity:f64,readings.value:f32 | grep -E '^type|^let parse'
printf '1,x,true\n2,,false\n' > "$dir/bare.csv"; "$zs" provide csv "$dir/bare.csv" --hasHeaders=false 2>&1 | sed "s|$at/||" | grep -E '^type|^/// From'
echo "--- the same text twice"
"$zs" provide json weather.json | diff - "$dir/Weather.zs" && "$zs" provide csv stocks.csv --separator=';' | diff - "$dir/Stocks.zs" && echo "deterministic"
echo "--- main.zs with the modules beside it"
cp main.zs weather.json stocks.csv "$dir/"
(cd "$dir" && ZS_NO_SERVER=1 "$zs" build --strict main.zs -o main && ./main)
echo "--- what a file holds stays data: a key, a header, a column, a register's name"
# a key that would end the backticks, the record and the line, and go on as code: refused
printf '{"a``: int }\\nlet pwned = 1\\ntype Junk = { ``b": 1}\n' > "$dir/hostile.json"
"$zs" provide json "$dir/hostile.json" 2>&1 | sed "s|$at/||"; echo "exit ${PIPESTATUS[0]}"
printf '"x\ny",b\n1,2\n' > "$dir/hostile.csv"
"$zs" provide csv "$dir/hostile.csv" 2>&1 | sed "s|$at/||"; echo "exit ${PIPESTATUS[0]}"
# a quote, a backtick, an interpolation and a backslash: a field in double backticks, which the
# derive reads and writes back as the key
cat > "$dir/odd.json" <<'JSON'
{"q\"$\"{1}\"`b\\": "it's"}
JSON
"$zs" provide json "$dir/odd.json" | sed "s|$at/||" | grep -E '^type|^/// From'
printf 'module Odd = import json "odd.json"\n\nlet main () =\n  match File.readAllText "odd.json" with\n  | Error e -> println e\n  | Ok text ->\n    match Odd.parse text with\n    | Ok r -> println (Odd.print r)\n    | Error e -> println e\n  0\n' > "$dir/odd_use.zs"
(cd "$dir" && ZS_NO_SERVER=1 "$zs" build --strict odd_use.zs -o odd_use && ./odd_use)
printf '"a""b",c\n"x""""y",2\n' > "$dir/odd.csv"
"$zs" provide csv "$dir/odd.csv" | sed "s|$at/||" | grep -E '^type|^/// From|^let private header'
printf 'CREATE TABLE t ("a\\" TEXT NOT NULL);\n' > "$dir/odd.sql"
"$zs" provide sql "$dir/odd.sql" | sed "s|$at/||"
printf '<device><name>x</name><peripherals><peripheral><name>P</name><baseAddress>0x40000000</baseAddress><registers><register><name>CR&#10;let pwned = 1&#10;//</name><addressOffset>0</addressOffset><fields><field><name>EN</name><bitOffset>0</bitOffset><bitWidth>1</bitWidth></field></fields></register></registers></peripheral></peripherals></device>\n' > "$dir/odd.svd"
"$zs" provide svd "$dir/odd.svd" > "$dir/Odd.zs"; echo "exit $?; the name in a comment: $(grep -c pwned "$dir/Odd.zs"), as code: $(grep -c '^ *let pwned' "$dir/Odd.zs")"
grep pwned "$dir/Odd.zs"
# POSIX's alone: Windows has no /dev/zero and starts no script as a program (test.sh leaves these
# lines out of provide.expected there)
if [ -z "$exe" ]; then
# a device is no file: read whole, it would never end
timeout 60 "$zs" provide json /dev/zero; echo "exit $?"
timeout 60 "$zs" provide c /dev/zero; echo "exit $?"
echo "--- a provider writing much to standard error, and one that doesn't end"
# over a pipe's worth of warnings before the module: read as they come, so neither side waits
cat > "$dir/bin/zs-provider-chatty" <<'SH'
#!/usr/bin/env bash
head -c 200000 /dev/zero | tr '\0' 'w' >&2
echo "// provided by chatty 1.0 from $1"
echo "let chatty = 1"
SH
# a provider stuck in a program it started, which holds its pipes: stopped at the limit
cat > "$dir/bin/zs-provider-stuck" <<'SH'
#!/usr/bin/env bash
sleep 30
SH
chmod +x "$dir/bin/zs-provider-chatty" "$dir/bin/zs-provider-stuck"
PATH="$dir/bin:$PATH" timeout 60 "$zs" provide chatty x; echo "exit $?"
PATH="$dir/bin:$PATH" ZS_PROVIDER_TIMEOUT=2 timeout 60 "$zs" provide stuck x; echo "exit $?"
fi
rm -rf "$dir"
