#!/usr/bin/env bash
# A scripted MCP session against `zs mcp` (newline-delimited JSON-RPC). Prints the text of
# each tool result, so the transcript stays readable.
set -u
zs=${1:-bin/zs}
# the docs tool's probe goes in this user's cache, not the shared temporary directory, where
# another user could make it a link to one of this user's files first
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
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
} | ZS_NO_SERVER=1 TMPDIR=$tmp "$zs" mcp | sed "s|$(pwd)|.|g" | while IFS= read -r line; do
  case "$line" in
    *'"tools":['*) printf '%s\n' "$line" | grep -o '"name":"[a-z_]*"' | tr '\n' ' '; echo ;;
    *'"content"'*) printf '%s\n' "$line" | sed 's/.*"text":"\(.*\)"}\],"isError":\(true\|false\).*/[\2] \1/' ;;
    *) printf '%s\n' "$line" | grep -o '"protocolVersion":"[^"]*"' ;;
  esac
done
echo "left in TMPDIR: $(ls -A "$tmp" | wc -l)"; ls -A "$tmp" >&2
