#!/usr/bin/env bash
# A scripted MCP session against `zs mcp` (newline-delimited JSON-RPC). Prints the text of
# each tool result, so the transcript stays readable.
set -u
zs=${1:-bin/zs}
# the docs tool's probe goes in this user's cache, not the shared temporary directory, where
# another user could make it a link to one of this user's files first
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# this checkout as zs names it: on Windows its own path (cygpath -m: D:/a/b, where Git Bash's pwd
# says /d/a/b)
here=$(cygpath -m "$PWD" 2>/dev/null || pwd)
{
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'
  echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"check","arguments":{"file":"tests/mcp/sample.zs"}}}'
  echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"check","arguments":{"file":"tests/mcp/broken.zs"}}}'
  echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"type_at","arguments":{"file":"tests/mcp/sample.zs","line":2,"column":5}}}'
  echo '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"type_at","arguments":{"file":"tests/mcp/sample.zs","line":5,"column":7}}}'
  echo '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"docs","arguments":{"query":"List.sort"}}}'
  echo '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"run","arguments":{"file":"tests/mcp/sample.zs"}}}'
  echo '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"run","arguments":{"file":"/etc/passwd"}}}'
  echo '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"definition","arguments":{"file":"tests/mcp/sample.zs","line":5,"column":21}}}'
  echo '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"definition","arguments":{"file":"tests/mcp/sample.zs","line":5,"column":17}}}'
  echo '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"explain","arguments":{"file":"tests/mcp/sample.zs","line":5,"column":21}}}'
  echo '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"explain","arguments":{"file":"tests/mcp/sample.zs","line":6,"column":3}}}'
} | ZS_NO_SERVER=1 TMPDIR=$tmp "$zs" mcp | sed "s|$here|.|g" | while IFS= read -r line; do
  # (isError's true or false as [a-z]*: BSD's sed, macOS's, has no \| in a basic regex)
  case "$line" in
    *'"tools":['*) printf '%s\n' "$line" | grep -o '"name":"[a-z_]*"' | tr '\n' ' '; echo ;;
    *'"content"'*) printf '%s\n' "$line" | sed 's/.*"text":"\(.*\)"}[]],"isError":\([a-z]*\).*/[\2] \1/' ;;
    *) printf '%s\n' "$line" | grep -o '"protocolVersion":"[^"]*"' ;;
  esac
done
echo "left in TMPDIR: $(ls -A "$tmp" | wc -l | tr -d ' ')"; ls -A "$tmp" >&2 # (tr: BSD's wc, macOS's, pads its count)
