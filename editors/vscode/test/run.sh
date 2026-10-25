#!/usr/bin/env bash
# The VS Code extension against a real zs: ZS=/path/to/zs CODE=/path/to/code editors/vscode/test/run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
zs=${ZS:-$(command -v zs)}
code=${CODE:-$(command -v code || echo "/Applications/Visual Studio Code.app/Contents/MacOS/Code")}
# the user data folder holds a socket whose path must be short: keep it under the extension
data="$here/.vscode-test"
rm -rf "$data"; mkdir -p "$data/ws"
cp "$here/test/main.zs" "$data/ws/"
mkdir -p "$data/user/User"
printf '{ "zsharp.path": "%s", "security.workspace.trust.enabled": false }\n' "$zs" > "$data/user/User/settings.json"
(cd "$here" && [ -d node_modules ] || npm ci --no-audit --no-fund)
"$code" --user-data-dir="$data/user" --extensions-dir="$data/ext" --disable-extensions \
  --extensionDevelopmentPath="$here" --extensionTestsPath="$here/test/smoke.js" "$data/ws"
