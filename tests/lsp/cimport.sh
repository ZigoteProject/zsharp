#!/usr/bin/env bash
# Hover and go-to-definition on an imported C function (tests/cimport): its Z# type, C prototype
# and header comment. Prints the two responses.
zs=${1:-bin/zs}
f=tests/cimport/main.zs
# this checkout as zs reads it: on Windows its own path (cygpath -m: D:/a/b, where Git Bash's pwd
# says /d/a/b), and a file URI's path then starts with the drive (file:///D:/a/b)
here=$(cygpath -m "$PWD" 2>/dev/null || pwd); root="file:///${here#/}"
uri="$root/$f"
src=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$f" | awk '{printf "%s\\n", $0}')
line=$(($(grep -n "point_add {" "$f" | head -1 | cut -d: -f1) - 1))
col=$(($(sed -n "$((line + 1))p" "$f" | grep -bo point_add | head -1 | cut -d: -f1) + 2))
frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":'$line',"character":'$col'}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"'"$uri"'"},"position":{"line":'$line',"character":'$col'}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | timeout 30 "$zs" lsp | tr '\r' '\n' | grep -o '{"jsonrpc".*"id":[23],.*' | sed 's/}Content-Length.*/}/'
