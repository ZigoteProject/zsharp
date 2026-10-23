#!/usr/bin/env bash
# Editing through the language server (0019): renaming a record field updates both modules that
# use it (its declaration, a literal, an update, a pattern and accesses), prepareRename, signature
# help inside a call, and code actions: a missing match case, an `open` for an unknown name and a
# binder's type. Prints the server's responses.
set -u
zs=${1:-bin/zs}
dir="$(pwd)/tests/lsp/edits"
open() { local uri="file://$dir/$1"; local src=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$dir/$1" | awk '{printf "%s\\n", $0}'); frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'; }
frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
main="file://$dir/main.zs"; shapes="file://$dir/Shapes.zs"
{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  open Shapes.zs
  open main.zs
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$shapes"'"},"position":{"line":1,"character":15},"newName":"px"}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/prepareRename","params":{"textDocument":{"uri":"'"$main"'"},"position":{"line":15,"character":11}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$main"'"},"position":{"line":15,"character":11},"newName":"let"}}'
  frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/signatureHelp","params":{"textDocument":{"uri":"'"$main"'"},"position":{"line":15,"character":18}}}'
  frame '{"jsonrpc":"2.0","id":6,"method":"textDocument/codeAction","params":{"textDocument":{"uri":"'"$main"'"},"range":{"start":{"line":7,"character":0},"end":{"line":7,"character":0}},"context":{"diagnostics":[{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":14}},"message":"match is not exhaustive; missing case: Square _"}]}}}'
  frame '{"jsonrpc":"2.0","id":7,"method":"textDocument/codeAction","params":{"textDocument":{"uri":"'"$main"'"},"range":{"start":{"line":10,"character":0},"end":{"line":10,"character":0}},"context":{"diagnostics":[{"range":{"start":{"line":10,"character":17},"end":{"line":10,"character":22}},"message":"unknown function '"'"'parse'"'"'"}]}}}'
  frame '{"jsonrpc":"2.0","id":8,"method":"textDocument/codeAction","params":{"textDocument":{"uri":"'"$main"'"},"range":{"start":{"line":13,"character":0},"end":{"line":13,"character":0}},"context":{"diagnostics":[]}}}'
  frame '{"jsonrpc":"2.0","id":9,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | sed 's/Content-Length: [0-9]*//' | grep -o '{.*}' | grep -v '"method"' | grep -v '"id":1,' | sed "s|file://$dir/||g"
