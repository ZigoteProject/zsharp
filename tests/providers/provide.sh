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
echo "--- errors (exit codes)"
"$zs" provide jsn weather.json; echo "exit $?"
"$zs" provide csv stocks.csv --seperator=';'; echo "exit $?"
"$zs" provide csv stocks.csv --types=volume:money; echo "exit $?"
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
