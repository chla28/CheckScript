// Test de bout en bout : un vrai VS Code (téléchargé, ou VSCODE_EXECUTABLE)
// avec l'extension en développement, un profil et un espace de travail
// temporaires, et le check-script de CHECK_SCRIPT (défaut : PATH).
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { runTests } from '@vscode/test-electron';

async function main() {
  const root = path.resolve(__dirname, '..', '..');
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'cs-vscode-'));
  fs.mkdirSync(path.join(work, '.vscode'));
  fs.writeFileSync(
    path.join(work, '.vscode', 'settings.json'),
    JSON.stringify({
      'checkScript.path': process.env.CHECK_SCRIPT ?? 'check-script',
      'checkScript.lang': 'fr',
      'checkScript.typingDelay': 100,
    }),
  );
  fs.writeFileSync(path.join(work, 'a.sh'), '#!/bin/bash\ncd /opt\negrep a f\negrep b f\n');
  fs.writeFileSync(path.join(work, 'Dockerfile'), 'FROM debian\nRUN cd /opt\n');
  try {
    await runTests({
      vscodeExecutablePath: process.env.VSCODE_EXECUTABLE,
      extensionDevelopmentPath: root,
      extensionTestsPath: path.join(root, 'out', 'test', 'suite.js'),
      launchArgs: [
        work,
        '--disable-extensions',
        '--user-data-dir',
        path.join(work, '.user'),
        '--disable-workspace-trust',
      ],
    });
  } catch (e) {
    console.error('Échec des tests de l\'extension :', e);
    process.exit(1);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

main();
