import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'helpers.dart';

class _Capture implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  late final IOSink sink = IOSink(this);

  @override
  Future<void> addStream(Stream<List<int>> s) => s.forEach(bytes.addAll);
  @override
  Future<void> close() async {}

  Future<String> text() async {
    await sink.flush();
    return utf8.decode(bytes);
  }
}

/// Chemins d'erreur de la ligne de commande (entrées invalides, fichiers
/// illisibles, écritures impossibles).
void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('cs_cli_err_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(int, String, String)> run(List<String> args) async {
    final out = _Capture(), err = _Capture();
    final code = await cli.run(['--lang', 'en', ...args],
        out: out.sink, err: err.sink, runner: noTools());
    return (code, await out.text(), await err.text());
  }

  File write(String name, String content) =>
      File('${tmp.path}/$name')..writeAsStringSync(content);

  const bad = '#!/bin/bash\nset -euo pipefail\neval "\$x"\n';
  const fixed = '#!/bin/bash\nset -euo pipefail\necho ok\n';

  group('configuration', () {
    test('--python-target invalide', () async {
      final f = write('a.sh', fixed);
      final (code, _, err) = await run(['--python-target', 'abc', f.path]);
      expect(code, cli.exitUsage);
      expect(err, contains('--python-target'));
    });

    test('--config : YAML invalide', () async {
      final f = write('a.sh', fixed);
      final c = write('bad.yaml', 'disabled_rules: [unclosed\n  : :');
      final (code, _, err) = await run(['-c', c.path, f.path]);
      expect(code, cli.exitUsage);
      expect(err, contains('Invalid configuration'));
    });

    test('--config : fichier inexistant', () async {
      final f = write('a.sh', fixed);
      final (code, _, err) =
          await run(['-c', '${tmp.path}/missing.yaml', f.path]);
      expect(code, cli.exitUsage);
      expect(err, contains('Unreadable configuration'));
    });
  });

  group('référence (baseline)', () {
    test('illisible', () async {
      final f = write('a.sh', fixed);
      final (code, _, err) =
          await run(['--baseline', '${tmp.path}/none.json', f.path]);
      expect(code, cli.exitUsage);
      expect(err, contains('Unreadable baseline'));
    });

    test('JSON invalide', () async {
      final f = write('a.sh', fixed);
      final b = write('base.json', '{ pas du json');
      final (code, _, err) = await run(['--baseline', b.path, f.path]);
      expect(code, cli.exitUsage);
      expect(err, isNotEmpty);
    });

    test('--baseline-update : resserre la référence puis la laisse en l\'état',
        () async {
      final f = write('a.sh', bad);
      final base = '${tmp.path}/base.json';
      await run(['-q', '-f', 'json', '-o', base, f.path]);
      f.writeAsStringSync(fixed);
      final (code, _, err) =
          await run(['-q', '--baseline', base, '--baseline-update', f.path]);
      expect(code, 0);
      expect(err, contains('Baseline tightened'));

      final (_, _, err2) =
          await run(['-q', '--baseline', base, '--baseline-update', f.path]);
      expect(err2, contains('Baseline unchanged'));
    });

    test('--baseline-update : nouveaux problèmes signalés', () async {
      final f = write('a.sh', fixed);
      final base = '${tmp.path}/base.json';
      await run(['-q', '-f', 'json', '-o', base, f.path]);
      f.writeAsStringSync(bad);
      final (_, _, err) =
          await run(['-q', '--baseline', base, '--baseline-update', f.path]);
      expect(err, contains('left as is'));
    });
  });

  group('entrées et sorties', () {
    test('dossier sans script reconnu', () async {
      write('notes.txt', 'rien\n');
      final (_, _, err) = await run([tmp.path]);
      expect(err, contains('No recognized script in'));
    });

    test('fichier non textuel ignoré', () async {
      final f = File('${tmp.path}/bin.sh')
        ..writeAsBytesSync([0x23, 0x21, 0xff, 0xfe, 0xfd, 0x00, 0x80]);
      final (code, _, err) = await run([f.path]);
      expect(code, isNot(0));
      expect(err, anyOf(contains('Non-text file skipped'), contains('Cannot')));
    });

    test('fichier inexistant', () async {
      final (code, _, err) = await run(['${tmp.path}/absent.sh']);
      expect(code, isNot(0));
      expect(err, isNotEmpty);
    });

    test('-o vers un emplacement non inscriptible', () async {
      final f = write('a.sh', fixed);
      // « Dossier parent » : un fichier ordinaire.
      final blocker = write('blocker', 'x');
      final (code, _, err) =
          await run(['-q', '-o', '${blocker.path}/r.md', f.path]);
      expect(code, cli.exitInput);
      expect(err, contains('Cannot write'));
    });

    test('--fix sur l\'entrée standard n\'est pas requis : --fix fichier ok',
        () async {
      final f = write('a.sh', '#!/bin/bash\negrep a f\n');
      final (code, _, _) = await run(['--fix', '-q', f.path]);
      expect(code, anyOf(0, 1));
      expect(f.readAsStringSync(), contains('grep -E'));
    });
  });
}
