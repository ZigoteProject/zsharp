#!/usr/bin/env bash
# A scripted LSP session on a provided module (0001): hover and completion on the sample's
# fields with no build run, the module's members after its name, a binding's provided type as a hint, a rename of a provided name refused with where it comes from, and
# the sample edited on disk: the client, told to watch it, says so, and completion has the new
# key. Prints the server's responses, then how many times it asked the client to watch files.
set -u
zs=$(realpath "${1:-bin/zs}"); dir=$(mktemp -d)
cp tests/providers/weather.json "$dir/weather.json"
# the directory as zs reads it: on Windows its own path (cygpath -m: C:/Users/..., where Git
# Bash's mktemp says /tmp/...), and a file URI's path then starts with the drive (file:///C:/...)
native=$(cygpath -m "$dir" 2>/dev/null || printf '%s' "$dir"); root="file:///${native#/}"
uri="$root/main.zs"
src='module Weather = import json \"weather.json\"\n\nlet main () =\n  match Weather.parse \"\" with\n  | Ok w -> println w.city\n  | Error e -> println e\n  0\n'

frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }

# the frames go through a pipe the server reads as it answers, its answers into a file; the sample
# is edited only once the rename (id 4) is answered there, so the earlier hover and completion see
# the sample as it was (an unnamed pipe: zs.exe, a Windows program, reads nothing from Git Bash's
# named ones)
answered() { for _ in $(seq 1 400); do grep -q "\"id\":$1," "$dir/raw" 2>/dev/null && return 0; sleep 0.05; done; echo "no answer to $1" >&2; }
{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":24}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":22}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":24},"newName":"town"}}'
  answered 4
  # the sample gains a key on disk (an edit in place as GNU's sed and BSD's, macOS's, both take
  # it), and the client reports the change
  sed 's/"city": "Oslo",/"city": "Oslo", "pressure": 1013,/' "$dir/weather.json" > "$dir/weather.new" \
    && mv "$dir/weather.new" "$dir/weather.json"
  frame '{"jsonrpc":"2.0","method":"workspace/didChangeWatchedFiles","params":{"changes":[{"uri":"'"$root"'/weather.json","type":2}]}}'
  frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":22}}}'
  # the provided module's members after its name, and its types in inlay hints
  frame '{"jsonrpc":"2.0","id":7,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":3,"character":16}}}'
  frame '{"jsonrpc":"2.0","id":8,"method":"textDocument/inlayHint","params":{"textDocument":{"uri":"'"$uri"'"},"range":{"start":{"line":0,"character":0},"end":{"line":8,"character":0}}}}'
  frame '{"jsonrpc":"2.0","id":6,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp > "$dir/raw" 2>/dev/null
tr -d '\r' < "$dir/raw" | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' > "$dir/transcript"
grep -v '"method"' "$dir/transcript" | sed "s|$uri|URI|g; s|$native|DIR|g" | sed -E 's/,"documentation":\{"kind":"markdown","value":"[^"]*"\}//g; s/("label":"[A-Za-z`-]+")[^}]*\}/\1}/g'
echo "asked to watch: $(grep -c 'client/registerCapability' "$dir/transcript"), with weather.json: $(grep -c 'weather.json' <(grep 'client/registerCapability' "$dir/transcript"))"
rm -rf "$dir"
