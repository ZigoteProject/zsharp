#!/usr/bin/env bash
# Two open documents, one using the other (tests/modules/main.zs and geometry.zs): a change to
# geometry.zs that removes what main.zs uses publishes main.zs's diagnostics again, with the error;
# putting it back clears them. Prints the diagnostics the server publishes, one per line.
set -u
zs=${1:-bin/zs}
main="file://$(pwd)/tests/modules/main.zs"
geo="file://$(pwd)/tests/modules/geometry.zs"
text() { sed 's/\\/\\\\/g; s/"/\\"/g' "$1" | awk '{printf "%s\\n", $0}'; }
msrc=$(text tests/modules/main.zs)
gsrc=$(text tests/modules/geometry.zs)
gbad=$(printf '%s' "$gsrc" | sed 's/let describe s =/let described s =/')

frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
open() { frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$1"'","languageId":"zsharp","version":1,"text":"'"$2"'"}}}'; }
change() { frame '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"'"$1"'","version":'"$3"'},"contentChanges":[{"text":"'"$2"'"}]}}'; }

{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  open "$main" "$msrc"
  open "$geo" "$gsrc"
  change "$geo" "$gbad" 2
  change "$geo" "$gsrc" 3
  frame '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' | grep publishDiagnostics | sed "s|file://$(pwd)/||g"
