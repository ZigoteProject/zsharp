#!/usr/bin/env bash
# Document URIs read as the files they name: a localhost authority, a percent-encoded space and a
# path through `..`, each opened with no errors. Prints each document's published diagnostics, by
# the URI the server writes for the file (an editor matches it to the document).
set -u
zs=$(realpath "${1:-bin/zs}")
# the real path: the server names a file by it (macOS's /var is a link to /private/var)
dir=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$dir"' EXIT
frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
opened() { frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$1"'","languageId":"zsharp","version":1,"text":"let main () = 0\n"}}}'; }
{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  opened "file://localhost$dir/local.zs"
  opened "file://$dir/with%20space.zs"
  opened "file://$dir/sub/../up.zs"
  frame '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | (cd "$dir" && ZS_NO_SERVER=1 "$zs" lsp) | grep -o '"uri":"[^"]*","diagnostics":\[[^]]*\]' | sed "s|$dir|DIR|"
