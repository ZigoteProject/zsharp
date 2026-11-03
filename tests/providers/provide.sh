#!/usr/bin/env bash
# zs provide (0001, track P's first step): the json and csv providers' modules printed from the
# samples here, the errors for what isn't a provider, an option or a file, and main.zs built
# with the two modules beside it (as a project keeps them in place of an import) and run
zs=$(realpath "${1:-bin/zs}"); dir=$(mktemp -d)
cd "$(dirname "$0")"
"$zs" provide --list
echo "--- json"
"$zs" provide json weather.json | tee "$dir/Weather.zs"
echo "--- csv"
"$zs" provide csv stocks.csv --separator=';' | tee "$dir/Stocks.zs"
echo "--- sql"
"$zs" provide sql schema.sql | tee "$dir/Db.zs"
echo "--- svd (GPIOA only; the module's head and one register)"
"$zs" provide svd ../../examples/mcu/stm32f401-part.svd --only=GPIOA > "$dir/Gpio.zs"; echo "exit $?, $(wc -l < "$dir/Gpio.zs") lines"
sed -n '1,8p' "$dir/Gpio.zs"; grep -n -A12 'type Bsrr' "$dir/Gpio.zs" | grep -E 'Bsrr|bs5|br15|read|write|modify' | head -8
echo "--- a provider on PATH: zs-provider-upper, a shell script"
mkdir -p "$dir/bin"
cat > "$dir/bin/zs-provider-upper" <<'SH'
#!/usr/bin/env bash
# a word per line in the file, as a constant: --prefix= names the constants
prefix=""
for a in "${@:2}"; do case $a in --prefix=*) prefix=${a#--prefix=} ;; *) echo "unknown option '$a' (prefix)" >&2; exit 1 ;; esac; done
[ -f "$1" ] || { echo "$1 not found" >&2; exit 1; }
echo "// provided by upper 1.0 from $1"
echo "// input: $1"
echo
while read -r w; do [ -n "$w" ] && echo "let $prefix$w = \"$(echo "$w" | tr a-z A-Z)\""; done < "$1"
SH
chmod +x "$dir/bin/zs-provider-upper"
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
printf 'CREATE TABLE empty ();\n' > "$dir/bad.sql"; "$zs" provide sql "$dir/bad.sql" 2>&1 | sed "s|$dir/||"; echo "exit ${PIPESTATUS[0]}"
printf '<device><name>x</name><peripherals><peripheral><name>A</name></peripheral>\n' > "$dir/bad.svd"; "$zs" provide svd "$dir/bad.svd" 2>&1 | sed "s|$dir/||"; echo "exit ${PIPESTATUS[0]}"
"$zs" provide json nowhere.json; echo "exit $?"
echo '{"a": [1, 2' > "$dir/broken.json"; "$zs" provide json "$dir/broken.json" 2>&1 | sed "s|$dir/||"; echo "exit ${PIPESTATUS[0]}"
printf 'a;b\n1;2;3\n' > "$dir/wide.csv"; "$zs" provide csv "$dir/wide.csv" --separator=';' 2>&1 | sed "s|$dir/||"; echo "exit ${PIPESTATUS[0]}"
"$zs" provide; echo "exit $?"
echo "--- options"
"$zs" provide json weather.json --root=Weather --types=humidity:f64,readings.value:f32 | grep -E '^type|^let parse'
printf '1,x,true\n2,,false\n' > "$dir/bare.csv"; "$zs" provide csv "$dir/bare.csv" --hasHeaders=false 2>&1 | sed "s|$dir/||" | grep -E '^type|^/// From'
echo "--- the same text twice"
"$zs" provide json weather.json | diff - "$dir/Weather.zs" && "$zs" provide csv stocks.csv --separator=';' | diff - "$dir/Stocks.zs" && echo "deterministic"
echo "--- main.zs with the modules beside it"
cp main.zs weather.json stocks.csv "$dir/"
(cd "$dir" && ZS_NO_SERVER=1 "$zs" build --strict main.zs -o main && ./main)
rm -rf "$dir"
