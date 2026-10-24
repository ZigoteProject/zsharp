#!/usr/bin/env bash
# Every mistake of a declaration (tests/err_many.zs, 0020): zs check's errors, one per line (its
# line: the message), then whether the language server publishes the same ones for the file.
set -u
zs=${1:-bin/zs}
f=tests/err_many.zs
uri="file://$(pwd)/$f"
text=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$f" | awk '{printf "%s\\n", $0}')
frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
check=$("$zs" check "$f" 2>&1 | sed -n "s|^$f:\([0-9]*\)[:0-9]*: error: |\1: |p")
lsp=$({
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$text"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | tr -d '\r' | grep -o '"diagnostics":\[.*\]' | tail -1 | sed 's/{"range"/\n&/g' \
  | sed -n 's/^{"range":{"start":{"line":\([0-9]*\),.*"severity":1,"source":"zs","message":"\([^"]*\)".*/\1 \2/p' \
  | while read -r n m; do printf '%s: %b\n' "$((n + 1))" "$m"; done)
echo "$check"
if [ "$check" = "$lsp" ]; then echo "the language server: the same"; else echo "the language server:"; echo "$lsp"; fi
