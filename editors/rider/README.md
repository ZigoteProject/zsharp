# Z# for Rider

A plugin for Rider (and the other JetBrains IDEs, 2025.2 or later): highlighting, bracket
matching, comments and indentation from the VS Code extension's TextMate grammar
(`../vscode/syntaxes`), plus the `zs lsp` language server through the IDE's LSP support:
diagnostics as you type, hover with types and docs (quick documentation), go to definition, find
usages, completion, inlay type hints, the structure view, rename, signature help (parameter info),
code actions (quick fixes) and formatting (Reformat Code).

## Build and install

1. Install `zs` (see `../zed/README.md`) and put it on `PATH`, or set its path in
   **Settings → Tools → Z#** (with the language server's arguments, `lsp` by default). The IDE
   reads `PATH` from the login shell, so a `zs` your shell finds is found.

2. Build the plugin (needs a JDK 25, which reads 2026.x's classes; the plugin itself runs on Java 21, so 2025.2 too. Gradle comes with the wrapper):

   ```sh
   cd editors/rider
   ./gradlew buildPlugin                                    # builds against Rider from JetBrains' repository
   ./gradlew buildPlugin -PplatformPath=$HOME/Applications/Rider.app   # or against a local install
   ```

   Then **Settings → Plugins → ⚙ → Install Plugin from Disk…** and choose
   `build/distributions/zsharp-rider-0.1.0.zip`. `./gradlew runIde` starts a sandboxed IDE with it.

3. Open a `.zs` file. The language server's status is in the status bar's language services widget,
   which can restart it; changing the settings restarts it too.

## The agent (MCP)

JetBrains' AI Assistant and Junie take MCP servers from their settings, not from plugins. Add
`zs mcp` there (AI Assistant: **Settings → Tools → AI Assistant → Model Context Protocol (MCP)**;
Junie: `.junie/mcp/mcp.json` in the project, or `~/.junie/mcp/mcp.json`):

```json
{ "mcpServers": { "zs": { "command": "/path/to/zs", "args": ["mcp"] } } }
```

Its tools take only files inside the project, but `run` runs the program it builds with your full
rights, unsandboxed.
