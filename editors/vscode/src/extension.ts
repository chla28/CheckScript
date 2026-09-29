// Extension CheckScript : lance `check-script lsp` (serveur LSP) pour les
// scripts shell et Python, les Dockerfile, Makefile et fichiers de CI, et
// affiche la note du script dans la barre d'état.
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;
let status: vscode.StatusBarItem;

/** Note par document, envoyée par le serveur (checkScript/score). */
const scores = new Map<string, { score: number; grade: string; findings: number }>();

function settings() {
  const c = vscode.workspace.getConfiguration('checkScript');
  return {
    path: c.get<string>('path') || 'check-script',
    lang: c.get<string>('lang') || undefined,
    profile: c.get<string>('profile') || undefined,
    analyzeOnType: c.get<boolean>('analyzeOnType', true),
    typingDelay: c.get<number>('typingDelay', 600),
  };
}

function french(): boolean {
  const lang = settings().lang ?? vscode.env.language;
  return lang.startsWith('fr');
}

function updateStatus() {
  const uri = vscode.window.activeTextEditor?.document.uri.toString();
  const s = uri ? scores.get(uri) : undefined;
  if (!s) {
    status.hide();
    return;
  }
  const note = french() ? s.score.toFixed(1).replace('.', ',') : s.score.toFixed(1);
  status.text = `$(checklist) ${note}/10 (${s.grade})`;
  status.tooltip = french()
    ? `CheckScript : ${s.findings} problème(s) — cliquer pour réanalyser`
    : `CheckScript: ${s.findings} issue(s) — click to re-analyse`;
  status.show();
}

async function start(context: vscode.ExtensionContext) {
  const s = settings();
  const serverOptions: ServerOptions = {
    command: s.path,
    args: ['lsp', ...(s.lang ? ['--lang', s.lang] : [])],
    transport: TransportKind.stdio,
  };
  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: 'file', language: 'shellscript' },
      { scheme: 'file', language: 'python' },
      { scheme: 'file', language: 'dockerfile' },
      { scheme: 'file', language: 'makefile' },
      // Le serveur ignore les fichiers YAML sans script intégré.
      { scheme: 'file', language: 'yaml' },
      { scheme: 'file', language: 'ansible' },
      { scheme: 'file', language: 'github-actions-workflow' },
    ],
    initializationOptions: {
      lang: s.lang,
      profile: s.profile,
      analyzeOnType: s.analyzeOnType,
      typingDelay: s.typingDelay,
    },
    synchronize: { configurationSection: 'checkScript' },
  };
  client = new LanguageClient('checkScript', 'CheckScript', serverOptions, clientOptions);
  try {
    await client.start();
  } catch (e) {
    client = undefined;
    const msg = french()
      ? `CheckScript : impossible de lancer « ${s.path} lsp ». Installer check-script ou régler checkScript.path.`
      : `CheckScript: cannot start "${s.path} lsp". Install check-script or set checkScript.path.`;
    const open = french() ? 'Réglages' : 'Settings';
    vscode.window.showErrorMessage(msg, open).then((a) => {
      if (a) vscode.commands.executeCommand('workbench.action.openSettings', 'checkScript.path');
    });
    return;
  }
  context.subscriptions.push(
    client.onNotification('checkScript/score', (p: {
      uri: string;
      score: number;
      grade: string;
      findings: number;
    }) => {
      scores.set(p.uri, { score: p.score, grade: p.grade, findings: p.findings });
      updateStatus();
    }),
  );
}

async function stop() {
  const c = client;
  client = undefined;
  scores.clear();
  if (c) await c.stop();
}

export async function activate(context: vscode.ExtensionContext) {
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 90);
  status.command = 'checkScript.analyze';
  context.subscriptions.push(
    status,
    vscode.window.onDidChangeActiveTextEditor(updateStatus),
    vscode.workspace.onDidCloseTextDocument((d) => {
      scores.delete(d.uri.toString());
      updateStatus();
    }),
    vscode.commands.registerCommand('checkScript.analyze', async () => {
      const uri = vscode.window.activeTextEditor?.document.uri.toString();
      if (client && uri) {
        // Commande du serveur (distincte de celle de l'extension).
        await client.sendRequest('workspace/executeCommand', {
          command: 'check-script.analyze',
          arguments: [uri],
        });
      }
    }),
    vscode.commands.registerCommand('checkScript.restart', async () => {
      await stop();
      await start(context);
    }),
    vscode.workspace.onDidChangeConfiguration(async (e) => {
      // Exécutable ou langue : il faut relancer le serveur.
      if (e.affectsConfiguration('checkScript.path') || e.affectsConfiguration('checkScript.lang')) {
        await stop();
        await start(context);
      }
    }),
  );
  await start(context);
}

export function deactivate(): Thenable<void> | undefined {
  return stop();
}
