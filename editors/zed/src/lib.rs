//! Zed extension for Z#: starts the `zs lsp` language server.
//!
//! `zs` is found on PATH, or set explicitly in Zed's settings:
//!   "lsp": { "zs": { "binary": { "path": "/path/to/zs", "arguments": ["lsp"] } } }

use zed_extension_api::{self as zed, settings::LspSettings, ContextServerId, LanguageServerId, Project, Result};

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

    // `zs mcp` for Zed's agent. It runs in the project directory, and its build/run tools only
    // touch files inside it. `zs` must be on Zed's PATH.
    fn context_server_command(&mut self, _id: &ContextServerId, _project: &Project) -> Result<zed::Command> {
        Ok(zed::Command {
            command: "zs".to_string(),
            args: vec!["mcp".to_string()],
            env: Vec::new(),
        })
    }
}

zed::register_extension!(ZSharp);
