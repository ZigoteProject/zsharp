#!/usr/bin/env bash
# A package's type provider (0001) in the servers: zs mcp and zs lsp without --trust neither build
# nor run it (an error at the import, nothing built); zs lsp --trust builds and runs it, which
# leaves its module; untrusted again, that module is used, with a warning. Prints each check's
# messages, and whether the provider's program was built.
set -u
zs=$(realpath "${1:-bin/zs}")
# the real path: the server names a file by it (macOS's /var is a link to /private/var)
dir=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/pkg" "$dir/shout"
cp tests/providers/pkg/zs.toml tests/providers/pkg/main.zs tests/providers/pkg/words.txt "$dir/pkg/"
cp tests/providers/shout/zs.toml tests/providers/shout/Main.zs "$dir/shout/"
# the directory as zs reads it: on Windows its own path (cygpath -m: C:/Users/..., where Git
# Bash's mktemp says /tmp/...), and a file URI's path then starts with the drive (file:///C:/...)
native=$(cygpath -m "$dir" 2>/dev/null || printf '%s' "$dir")
uri="file:///${native#/}/pkg/main.zs"
src=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$dir/pkg/main.zs" | awk '{printf "%s\\n", $0}')

frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
# a session that opens main.zs: the messages of the diagnostics published for it
lsp() {
  { frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
    frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$uri"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
    frame '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
    frame '{"jsonrpc":"2.0","method":"exit"}'
  } | (cd "$dir/pkg" && ZS_NO_SERVER=1 "$zs" lsp "$@") | grep -o '"message":"[^"]*"' | sed 's/^"message":"\(.*\)"$/  \1/'
}
# the MCP check of main.zs: its text
mcp() {
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check","arguments":{"file":"main.zs"}}}' \
    | (cd "$dir/pkg" && ZS_NO_SERVER=1 "$zs" mcp "$@") | grep -o '"text":"[^"]*"' | sed 's/^"text":"\(.*\)"$/  \1/'
}
built() { if [ -e "$dir/pkg/.zs-cache/providers/bin/zs-provider-shout" ]; then echo yes; else echo no; fi; }

echo "--- zs mcp, not trusted"
mcp
echo "--- zs lsp, not trusted"
lsp
echo "built: $(built)"
echo "--- zs lsp --trust"
lsp --trust
echo "built: $(built)"
echo "--- zs lsp, not trusted, after it"
lsp
echo "--- zs mcp, not trusted, after it"
mcp
