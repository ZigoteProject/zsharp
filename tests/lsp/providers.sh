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

{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":24}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":22}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":24},"newName":"town"}}'
  # the sample gains a key on disk, and the client reports the change
  sed -i 's/"city": "Oslo",/"city": "Oslo", "pressure": 1013,/' "$dir/weather.json"
  frame '{"jsonrpc":"2.0","method":"workspace/didChangeWatchedFiles","params":{"changes":[{"uri":"file://'"$dir"'/weather.json","type":2}]}}'
  frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":22}}}'
  frame '{"jsonrpc":"2.0","id":6,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' > "$dir/transcript"
grep -v '"method"' "$dir/transcript" | sed "s|$uri|URI|g; s|$dir|DIR|g" | sed -E 's/("label":"[a-z`-]+")[^}]*\}/\1}/g'
echo "asked to watch: $(grep -c 'client/registerCapability' "$dir/transcript"), with weather.json: $(grep -c 'weather.json' <(grep 'client/registerCapability' "$dir/transcript"))"
rm -rf "$dir"
