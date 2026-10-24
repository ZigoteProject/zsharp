# Z# for Zed

Syntax highlighting, outline, bracket matching and indentation (from the tree-sitter grammar in
`../tree-sitter-zsharp`), plus the `zs` language server: diagnostics as you type, hover with
types (and trait constraints) and docs, go to definition, references, completion, inlay type
hints, document symbols and formatting. Zed's agent gets the `zs mcp` context server.

## Install (dev extension)

1. Install `zs` where Zed can run it (a native binary with its library and runtime beside it; it
   needs no .NET and, for `import c`, finds libclang when there is one and reads the saved
   import when there isn't, which matters for the Flatpak build of Zed):

   ```sh
   ./dev ./test.sh                       # or any build of bin/zs
   src/install.sh bin/zs dist/zs
   ```

   Put `dist/zs` on `PATH`, or set the path in Zed's settings:

   ```json
   { "lsp": { "zs": { "binary": { "path": "/path/to/zsharp/dist/zs/zs" } } } }
   ```

2. Generate the parser once (Zed compiles `src/parser.c`, it doesn't run the generator), and
   commit it: `./dev bash -c 'cd editors/tree-sitter-zsharp && tree-sitter generate'`.
   Then, in `extension.toml`, set `[grammars.zsharp] rev` to a commit of this repository that contains
   `editors/tree-sitter-zsharp` (`git rev-parse HEAD`).

3. In Zed: command palette → `zed: install dev extension` → choose `editors/zed`. Zed builds the
   Rust part for `wasm32-wasip2` with the host's Rust and the grammar with wasi-sdk (downloaded
   automatically). Fedora doesn't package the `wasm32-wasip2` target, so use rustup:
   `curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --target wasm32-wasip2`,
   then restart Zed so it picks up `~/.cargo/bin` from your shell.

4. Zed's agent gets the `zs` context server (`zs mcp`): `check`, `type_at`, `docs`, `build`,
   `run`, `emit_llvm` and `format`. Enable it in the agent panel's settings.

5. Open a `.zs` file. `zed: open log` shows the extension's and the server's messages.

The queries in `languages/zsharp/` are copies of `../tree-sitter-zsharp/queries/`; keep them in
step (`./test.sh` checks).

## Zed from Flatpak

The Flatpak's sandbox has `PATH=/app/bin:/usr/bin` and no clang, so:

- Give Zed the path to the self-contained `zs` (`dist/zs/zs` after the publish step) in
  `settings.json`. The language server and the agent's context server both use it:

  ```json
  {
    "lsp": { "zs": { "binary": { "path": "/path/to/zsharp/dist/zs/zs", "arguments": ["lsp"] } } },
    "context_servers": { "zs": { "command": "/path/to/zsharp/dist/zs/zs", "args": ["mcp"] } }
  }
  ```

- With a `path` in the settings Zed runs that binary itself, with the settings' arguments (the
  extension isn't asked). Without arguments, `zs` detects LSP or MCP from the first byte, but
  giving them is clearer.
- The agent's `build` and `run` tools need clang, which the sandbox lacks. `check`, `type_at`,
  `docs`, `format` and `emit_llvm` work. Run programs from a terminal (`./dev bin/zs run …`).

Checked: the published `zs` runs inside the sandbox (`flatpak run --command=sh dev.zed.Zed`).
The dev container has Fedora's `wasm32-wasip1` target only, so it checks that the Rust part
compiles with `./dev bash -c 'cd editors/zed && cargo build --release --target wasm32-wasip1'`;
Zed itself builds it for `wasm32-wasip2`.
