#!/usr/bin/env bash
# A scripted LSP session over effects (phase 10): hover shows a function's effects and an
# operation's type, an inlay hint a function's inferred effects before its `=`, and an operation's
# definition and references (the perform and the clause). Prints the server's responses.
set -u
zs=${1:-bin/zs}
uri="file://$(pwd)/tests/lsp/effects.zs"
src=$(sed 's/\\/\\\\/g; s/"/\\"/g' tests/lsp/effects.zs | awk '{printf "%s\\n", $0}')

frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }

{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":3,"character":5}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":4}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/inlayHint","params":{"textDocument":{"uri":"'"$uri"'"},"range":{"start":{"line":0,"character":0},"end":{"line":20,"character":0}}}}'
  frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/definition","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":4}}}'
  frame '{"jsonrpc":"2.0","id":6,"method":"textDocument/references","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":1,"character":12},"context":{"includeDeclaration":true}}}'
  frame '{"jsonrpc":"2.0","id":7,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' | grep -v '"method"' | sed "s|$uri|URI|g; s|$(pwd)|.|g"
