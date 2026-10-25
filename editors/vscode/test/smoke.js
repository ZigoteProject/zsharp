// Run by run.sh inside VS Code: opens main.zs and asks the zs language server for each feature.
const vscode = require('vscode');
const sleep = ms => new Promise(r => setTimeout(r, ms));

exports.run = async () => {
  const uri = vscode.Uri.joinPath(vscode.workspace.workspaceFolders[0].uri, 'main.zs');
  const at = (line, ch) => new vscode.Position(line, ch);
  const ask = (cmd, ...args) => vscode.commands.executeCommand(cmd, uri, ...args);
  const failed = [];
  const check = (name, ok) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}`); if (!ok) failed.push(name); };

  const doc = await vscode.workspace.openTextDocument(uri);
  await vscode.window.showTextDocument(doc);
  check('language', doc.languageId === 'zsharp');
  let diags = [];
  for (let i = 0; i < 60 && diags.length === 0; i++) { await sleep(500); diags = vscode.languages.getDiagnostics(uri); }
  check('diagnostics', diags.length === 1 && diags[0].range.start.line === 1);
  const hover = await ask('vscode.executeHoverProvider', at(0, 5));
  check('hover', hover.some(h => h.contents.some(c => (c.value || '').includes('int -> int -> int'))));
  check('symbols', (await ask('vscode.executeDocumentSymbolProvider') || []).some(s => s.name === 'add'));
  check('inlay hints', (await ask('vscode.executeInlayHintProvider', new vscode.Range(0, 0, 3, 0)) || []).length > 0);
  check('references', (await ask('vscode.executeReferenceProvider', at(0, 5)) || []).length >= 2);
  check('completion', ((await ask('vscode.executeCompletionItemProvider', at(2, 26))) || { items: [] }).items.length > 0);
  check('rename', (await ask('vscode.executeDocumentRenameProvider', at(0, 5), 'plus')).size > 0);
  check('formatting', (await ask('vscode.executeFormatDocumentProvider', { tabSize: 2, insertSpaces: true }) || []).length > 0);
  await vscode.commands.executeCommand('zsharp.restart');
  check('restart', true);
  if (failed.length) throw new Error(`failed: ${failed.join(', ')}`);
};
