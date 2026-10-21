# Z# for Zed

Syntax highlighting, outline, bracket matching and indentation (from the tree-sitter grammar in
`../tree-sitter-zsharp`), plus the `zs` language server: diagnostics as you type, hover types
(with trait constraints) and inlay type hints.

## Install (dev extension)

1. Build a self-contained `zs` (it then runs without a .NET installation, which matters for the
   Flatpak build of Zed, whose sandbox has no `dotnet`):

   ```sh
   ./dev dotnet publish src -c Release -r linux-x64 --self-contained -o dist/zs
   ```

   Put `dist/zs` on `PATH`, or set the path in Zed's settings:

   ```json
   { "lsp": { "zs": { "binary": { "path": "/home/you/zsharp/dist/zs/zs" } } } }
   ```

2. Generate the parser once (Zed compiles `src/parser.c`, it doesn't run the generator), and
   commit it: `./dev bash -c 'cd editors/tree-sitter-zsharp && tree-sitter generate'`.
   Then, in `extension.toml`, set `[grammars.zsharp] rev` to a commit of this repository that contains
   `editors/tree-sitter-zsharp` (`git rev-parse HEAD`).

3. In Zed: command palette → `zed: install dev extension` → choose `editors/zed`. Zed builds the
   Rust part (it needs `rustup`; the Flatpak uses its own) and the grammar.

4. Zed's agent gets the `zs` context server (`zs mcp`): `check`, `type_at`, `docs`, `build`,
   `run` and `emit_llvm`. Enable it in the agent panel's settings.

5. Open a `.zs` file. `zed: open log` shows the extension's and the server's messages.

The queries in `languages/zsharp/` are copies of `../tree-sitter-zsharp/queries/`; keep them in
step (`./test.sh` checks).

## Zed from Flatpak

The Flatpak's sandbox has `PATH=/app/bin:/usr/bin` and no clang, so:

- Give Zed the path to the self-contained `zs` (`dist/zs/zs` after the publish step) in
  `settings.json`. The language server and the agent's context server both use it:

  ```json
  {
    "lsp": { "zs": { "binary": { "path": "/path/to/zsharp/dist/zs/zs" } } },
    "context_servers": { "zs": { "command": { "path": "/path/to/zsharp/dist/zs/zs" } } }
  }
  ```

- The agent's `build` and `run` tools need clang, which the sandbox lacks. `check`, `type_at`,
  `docs`, `format` and `emit_llvm` work. Run programs from a terminal (`./dev bin/zs run …`).

Checked: the published `zs` runs inside the sandbox (`flatpak run --command=sh dev.zed.Zed`),
and the extension builds for `wasm32-wasip1`
(`./dev bash -c 'cd editors/zed && cargo build --release --target wasm32-wasip1'`).
