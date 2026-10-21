//! Zed extension for Z#: starts the `zs lsp` language server.
//!
//! `zs` is found on PATH, or set explicitly in Zed's settings:
//!   "lsp": { "zs": { "binary": { "path": "/path/to/zs", "arguments": ["lsp"] } } }

use zed_extension_api::{self as zed, settings::LspSettings, LanguageServerId, Result};

struct ZSharp;

impl zed::Extension for ZSharp {
    fn new() -> Self {
        ZSharp
    }

    fn language_server_command(&mut self, id: &LanguageServerId, worktree: &zed::Worktree) -> Result<zed::Command> {
        let binary = LspSettings::for_worktree(id.as_ref(), worktree)
            .ok()
            .and_then(|s| s.binary);

        let path = binary
            .as_ref()
            .and_then(|b| b.path.clone())
            .or_else(|| worktree.which("zs"))
            .ok_or_else(|| {
                "zs was not found on PATH. Build it (dotnet publish src -c Release -r linux-x64 --self-contained -o ~/.local/zs) \
                 and add it to PATH, or set lsp.zs.binary.path in Zed's settings."
                    .to_string()
            })?;

        let args = binary
            .and_then(|b| b.arguments)
            .unwrap_or_else(|| vec!["lsp".to_string()]);

        Ok(zed::Command {
            command: path,
            args,
            env: worktree.shell_env(),
        })
    }
}

zed::register_extension!(ZSharp);
