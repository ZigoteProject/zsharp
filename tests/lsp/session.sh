#!/usr/bin/env bash
# A scripted LSP session against `zs lsp`: open a document, ask for hover, inlay hints and
# symbols, then edit it to contain an error. Prints the server's responses, one per line.
set -u
zs=${1:-bin/zs}
uri="file://$(pwd)/tests/lsp/sample.zs"
src=$(sed 's/\\/\\\\/g; s/"/\\"/g' tests/lsp/sample.zs | awk '{printf "%s\\n", $0}')
bad=$(printf '%s' "$src" | sed 's/let total = add 1 2/let total = add 1 true/')

frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }

{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":1,"character":5}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":7}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/inlayHint","params":{"textDocument":{"uri":"'"$uri"'"},"range":{"start":{"line":0,"character":0},"end":{"line":20,"character":0}}}}'
  frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"'"$uri"'"}}}'
  frame '{"jsonrpc":"2.0","id":10,"method":"textDocument/definition","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":15}}}'
  frame '{"jsonrpc":"2.0","id":11,"method":"textDocument/references","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":4,"character":7},"context":{"includeDeclaration":true}}}'
  frame '{"jsonrpc":"2.0","id":12,"method":"textDocument/definition","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":7,"character":24}}}'
  frame '{"jsonrpc":"2.0","id":14,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":7,"character":24}}}'
  frame '{"jsonrpc":"2.0","id":15,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":6,"character":17}}}'
  frame '{"jsonrpc":"2.0","id":13,"method":"textDocument/completion","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":6,"character":16}}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"'"$uri"'","version":2},"contentChanges":[{"text":"'"$bad"'"}]}}'
  frame '{"jsonrpc":"2.0","id":6,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' | sed "s|$uri|URI|g; s|file://$(pwd)/bin/|file://ZS/|g; s|$(pwd)|.|g"
