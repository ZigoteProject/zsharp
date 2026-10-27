# Z# for VS Code

Syntax highlighting (a TextMate grammar, the counterpart of the tree-sitter grammar's queries),
bracket matching, comments and indentation, plus the `zs` language server: diagnostics as you
type, hover with types (and trait constraints) and docs, go to definition, references, completion,
inlay type hints, document symbols (the outline and breadcrumbs), rename, signature help, code
actions and formatting. The agent (Copilot Chat's agent mode) gets the `zs mcp` server.

The same grammar and language configuration give the Rider plugin (`../rider`) its highlighting.

## Install

1. Install `zs` where VS Code can run it (as for Zed, see `../zed/README.md`):

   ```sh
   ./dev ./test.sh                       # or any build of bin/zs
   src/install.sh bin/zs dist/zs
   ```

   Put `dist/zs` on `PATH`, or set `"zsharp.path": "/path/to/zsharp/dist/zs/zs"` in the settings.

2. Package and install the extension (needs Node.js):

   ```sh
   cd editors/vscode
   npm ci
   npx @vscode/vsce package --allow-missing-repository --skip-license
   code --install-extension zsharp-0.1.0.vsix
   ```

   Or, for development, open `editors/vscode` in VS Code and press F5.

3. The agent gets the `zs` MCP server (`zs mcp`): `check`, `type_at`, `docs`, `build`, `run`,
   `emit_llvm` and `format`. Enable it in the chat's tool picker (**MCP: List Servers** shows it).
   Its tools take only files inside the workspace, but `run` runs the program it builds with your
   full rights, unsandboxed.

4. Open a `.zs` file. **Output → Z#** shows the server's messages; **Z#: Restart Language Server**
   restarts it (changing a `zsharp.*` setting restarts it too).

## Settings

| Setting | Default | |
|---|---|---|
| `zsharp.path` | `""` | `zs`, for both servers; empty: `zs` on `PATH` |
| `zsharp.lsp.arguments` | `["lsp"]` | arguments that start the language server |
| `zsharp.mcp.arguments` | `["mcp"]` | arguments that start the MCP server |
| `zsharp.allocationHints` | `false` | what each line allocates, reuses or may copy, as inlay hints, and a function's summary on hover |

The extension stays off in an untrusted workspace (Restricted Mode): a workspace's settings can
set `zsharp.path`, so trusting the workspace is trusting the program it names. Highlighting still
works there.

## Checks

`./test.sh` checks that the grammar's keywords are the tree-sitter highlights' keywords.
`ZS=/path/to/zs test/run.sh` starts VS Code with the extension on `test/main.zs` and asks the
server for each feature (diagnostics, hover, symbols, inlay hints, references, completion, rename,
formatting, restart).
