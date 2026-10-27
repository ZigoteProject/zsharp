// VS Code extension for Z#: starts the `zs lsp` language server and offers `zs mcp` to the agent.
//
// `zs` is found on PATH, or set explicitly in the settings: "zsharp.path": "/path/to/zs"

const vscode = require('vscode');
const { LanguageClient } = require('vscode-languageclient/node');

let client;

function settings() {
  const c = vscode.workspace.getConfiguration('zsharp');
  // an empty argument list is still `zs lsp` / `zs mcp`, as in the Zed extension
  const args = (key, dflt) => {
    const a = c.get(key);
    return Array.isArray(a) && a.length > 0 ? a : [dflt];
  };
  return {
    path: c.get('path') || 'zs',
    lsp: args('lsp.arguments', 'lsp'),
    mcp: args('mcp.arguments', 'mcp'),
    allocationHints: c.get('allocationHints') === true,
  };
}

async function start() {
  const s = settings();
  const server = { command: s.path, args: s.lsp };
  client = new LanguageClient('zs', 'Z#', { run: server, debug: server }, {
    documentSelector: [{ scheme: 'file', language: 'zsharp' }],
    // what each line allocates, reuses or may copy, as inlay hints (0011)
    initializationOptions: { allocationHints: s.allocationHints },
  });
  try {
    await client.start();
  } catch (e) {
    vscode.window.showErrorMessage(
      `Z#: could not start ${s.path} (${e.message}). Install zs (./dev ./test.sh, then ` +
      'src/install.sh bin/zs ~/.local/zs) and add it to PATH, or set zsharp.path.');
  }
}

// restarts run one after another, so quick setting changes can't leave two servers running
let restarting = Promise.resolve();
function restart() {
  restarting = restarting.then(async () => {
    if (client) await client.stop().catch(() => {});
    await start();
  });
  return restarting;
}

function activate(context) {
  const changed = new vscode.EventEmitter();
  context.subscriptions.push(
    vscode.commands.registerCommand('zsharp.restart', restart),
    vscode.workspace.onDidChangeConfiguration(e => {
      if (!e.affectsConfiguration('zsharp')) return;
      changed.fire();
      restart();
    }),
    // `zs mcp` for the agent. Its tools take only files inside the project, but `run` runs the
    // program it builds with the user's full rights, unsandboxed.
    vscode.lm.registerMcpServerDefinitionProvider('zsharp.mcp', {
      onDidChangeMcpServerDefinitions: changed.event,
      provideMcpServerDefinitions: () => {
        const s = settings();
        return [new vscode.McpStdioServerDefinition('zs', s.path, s.mcp)];
      },
    }),
  );
  return start();
}

function deactivate() {
  return client && client.stop();
}

module.exports = { activate, deactivate };
