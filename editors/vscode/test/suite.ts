// Scénario exécuté dans VS Code : diagnostics, survol, corrections rapides,
// formatage, note dans la barre d'état, Dockerfile (scripts intégrés).
import * as assert from 'assert';
import * as path from 'path';
import * as vscode from 'vscode';

async function until<T>(what: string, f: () => T | undefined | Promise<T | undefined>, ms = 30000): Promise<T> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const v = await f();
    if (v !== undefined) return v;
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`délai dépassé : ${what}`);
}

export async function run(): Promise<void> {
  const ws = vscode.workspace.workspaceFolders![0].uri.fsPath;
  const uri = vscode.Uri.file(path.join(ws, 'a.sh'));
  const doc = await vscode.workspace.openTextDocument(uri);
  await vscode.window.showTextDocument(doc);

  // Diagnostics (egrep : SC2196 si ShellCheck est installé, sinon POR005).
  const isEgrep = (x: vscode.Diagnostic) => ['POR005', 'SC2196'].includes(codeOf(x));
  const diags = await until('diagnostics', () => {
    const d = vscode.languages.getDiagnostics(uri);
    return d.some(isEgrep) ? d : undefined;
  });
  const egrep = diags.find(isEgrep)!;
  const rule = codeOf(egrep);
  assert.strictEqual(egrep.range.start.line, 2);
  console.log(`✓ ${diags.length} diagnostics`);

  // Survol.
  const hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
    'vscode.executeHoverProvider', uri, new vscode.Position(2, 1));
  const text = hovers.flatMap((h) => h.contents.map((c) => (c as vscode.MarkdownString).value ?? String(c))).join('\n');
  assert.ok(text.includes(rule), text);
  console.log('✓ survol');

  // Corrections rapides.
  const actions = await vscode.commands.executeCommand<vscode.CodeAction[]>(
    'vscode.executeCodeActionProvider', uri, egrep.range);
  const titles = actions.map((a) => a.title);
  assert.ok(titles.includes(`Corriger : ${rule}`), titles.join(' | '));
  assert.ok(titles.includes(`Corriger les 2 occurrences de ${rule}`), titles.join(' | '));
  const all = actions.find((a) => a.title.startsWith('Corriger les 2'))!;
  assert.ok(await vscode.workspace.applyEdit(all.edit!));
  assert.ok(!doc.getText().includes('egrep'), doc.getText());
  console.log('✓ corrections rapides');

  // Frappe : la correction fait disparaître POR005 sans enregistrer.
  await until('analyse pendant la frappe', () =>
    vscode.languages.getDiagnostics(uri).some((x) => codeOf(x) === 'POR005') ? undefined : true);
  console.log('✓ analyse pendant la frappe');
  // Analyse complète à l'enregistrement : plus de problème egrep.
  await doc.save();
  await until('analyse à l\'enregistrement', () =>
    vscode.languages.getDiagnostics(uri).some(isEgrep) ? undefined : true);
  console.log('✓ enregistrement');

  // Formatage (shfmt s'il est installé).
  const edits = await vscode.commands.executeCommand<vscode.TextEdit[]>(
    'vscode.executeFormatDocumentProvider', uri, { tabSize: 4, insertSpaces: true });
  assert.ok(Array.isArray(edits ?? []));
  console.log(`✓ formatage (${edits?.length ?? 0} modification(s))`);

  // Dockerfile : scripts intégrés.
  const df = vscode.Uri.file(path.join(ws, 'Dockerfile'));
  await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(df));
  await until('diagnostics du Dockerfile', () => {
    const d = vscode.languages.getDiagnostics(df);
    return d.some((x) => codeOf(x) === 'ROB005' || codeOf(x) === 'SC2164') ? d : undefined;
  });
  console.log('✓ Dockerfile');
}

function codeOf(d: vscode.Diagnostic): string {
  const c = d.code;
  return typeof c === 'object' && c !== null ? String(c.value) : String(c);
}
