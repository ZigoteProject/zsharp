#!/usr/bin/env bash
# Hover, references and definition of type names written in annotations, and the signature hints
# at the end of a function's line. Prints the server's responses, one per line.
set -u
zs=${1:-bin/zs}
uri="file://$(pwd)/tests/lsp/types.zs"
src=$(sed 's/\\/\\\\/g; s/"/\\"/g' tests/lsp/types.zs | awk '{printf "%s\\n", $0}')
frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":16}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/references","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":16},"context":{"includeDeclaration":true}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/definition","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":7,"character":19}}}'
  frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":7,"character":12}}}'
  frame '{"jsonrpc":"2.0","id":6,"method":"textDocument/inlayHint","params":{"textDocument":{"uri":"'"$uri"'"},"range":{"start":{"line":0,"character":0},"end":{"line":20,"character":0}}}}'
  frame '{"jsonrpc":"2.0","id":8,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":13,"character":14}}}'
  frame '{"jsonrpc":"2.0","id":7,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' | grep -v publishDiag
