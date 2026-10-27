#!/usr/bin/env bash
# A scripted LSP session with allocation hints on (0011, 0026): each line's hint (what it
# allocates, the cell it reuses, the array it may copy, with the objects in the tooltip; none in
# the [<NoAlloc>] function), the summary hover shows on a function, and the hints again after an
# edit. Prints the server's responses.
set -u
zs=${1:-bin/zs}
uri="file://$(pwd)/tests/lsp/hints.zs"
src=$(sed 's/\\/\\\\/g; s/"/\\"/g' tests/lsp/hints.zs | awk '{printf "%s\\n", $0}')
# the report's line built from one string: one concatenation
edited=$(printf '%s' "$src" | sed 's/out <- out + \$\\"{name}: {qty}\\\\n\\"/out <- out + name/')

frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }

{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"initializationOptions":{"allocationHints":true}}}'
  frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/inlayHint","params":{"textDocument":{"uri":"'"$uri"'"},"range":{"start":{"line":0,"character":0},"end":{"line":40,"character":0}}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":5,"character":9}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":20,"character":5}}}'
  frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":32,"character":35}}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"'"$uri"'","version":2},"contentChanges":[{"text":"'"$edited"'"}]}}'
  frame '{"jsonrpc":"2.0","id":6,"method":"textDocument/inlayHint","params":{"textDocument":{"uri":"'"$uri"'"},"range":{"start":{"line":16,"character":0},"end":{"line":16,"character":0}}}}'
  frame '{"jsonrpc":"2.0","id":7,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' | grep -v '"method"' | sed "s|$uri|URI|g; s|$(pwd)|.|g"
