#!/usr/bin/env bash
# A scripted LSP session on a provided module (0001): hover and completion on the sample's
# fields with no build run, a rename of a provided name refused with where it comes from, and
# the sample edited on disk: the client, told to watch it, says so, and completion has the new
# key. Prints the server's responses, then how many times it asked the client to watch files.
set -u
zs=$(realpath "${1:-bin/zs}"); dir=$(mktemp -d)
cp tests/providers/weather.json "$dir/weather.json"
uri="file://$dir/main.zs"
src='module Weather = import json \"weather.json\"\n\nlet main () =\n  match Weather.parse \"\" with\n  | Ok w -> println w.city\n  | Error e -> println e\n  0\n'

frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }

# the frames go through a pipe the server reads as it answers; the sample is edited only once the
# rename (id 4) is answered, so the earlier hover and completion see the sample as it was
mkfifo "$dir/in"
"$zs" lsp < "$dir/in" > "$dir/raw" 2>/dev/null &
server=$!
exec 3> "$dir/in"
send() { frame "$1" >&3; }
answered() { for _ in $(seq 1 400); do grep -q "\"id\":$1," "$dir/raw" 2>/dev/null && return 0; sleep 0.05; done; echo "no answer to $1" >&2; }
send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
send '{"jsonrpc":"2.0","method":"initialized","params":{}}'
send '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
send '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":24}}}'
send '{"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":22}}}'
send '{"jsonrpc":"2.0","id":4,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":24},"newName":"town"}}'
answered 4
# the sample gains a key on disk (an edit in place as GNU's sed and BSD's, macOS's, both take it),
# and the client reports the change
sed 's/"city": "Oslo",/"city": "Oslo", "pressure": 1013,/' "$dir/weather.json" > "$dir/weather.new" \
  && mv "$dir/weather.new" "$dir/weather.json"
send '{"jsonrpc":"2.0","method":"workspace/didChangeWatchedFiles","params":{"changes":[{"uri":"file://'"$dir"'/weather.json","type":2}]}}'
send '{"jsonrpc":"2.0","id":5,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":22}}}'
send '{"jsonrpc":"2.0","id":6,"method":"shutdown"}'
send '{"jsonrpc":"2.0","method":"exit"}'
exec 3>&-
wait $server
tr -d '\r' < "$dir/raw" | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' > "$dir/transcript"
grep -v '"method"' "$dir/transcript" | sed "s|$uri|URI|g; s|$dir|DIR|g" | sed -E 's/("label":"[a-z`-]+")[^}]*\}/\1}/g'
echo "asked to watch: $(grep -c 'client/registerCapability' "$dir/transcript"), with weather.json: $(grep -c 'weather.json' <(grep 'client/registerCapability' "$dir/transcript"))"
rm -rf "$dir"
