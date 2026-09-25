import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'helpers.dart';

class _Sink implements StreamConsumer<List<int>> {
  final out = StringBuffer();
  @override
  Future<void> addStream(Stream<List<int>> s) =>
      s.forEach((b) => out.write(utf8.decode(b)));
  @override
  Future<void> close() async {}
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_011_'));
  tearDown(() => tmp.delete(recursive: true));

  group('faux positifs', () {
    test('anonymisation : chaînes et jetons longs masqués', () {
      expect(anonymizeCode('curl -H "Authorization: Bearer abc" \$URL'),
          'curl -H "…" \$URL');
      expect(
          anonymizeCode("KEY='x' ; id=aZ3kQ9mW2xV7pL4nR8tY"), "KEY='…' ; id=…");
      expect(anonymizeCode('echo ok'), 'echo ok');
    });

    test('cas enregistré : contexte anonymisé, ligne à secret exclue',
        () async {
      final r = await Engine(runner: noTools()).analyze(script(
          '#!/bin/bash\nPASSWORD="S3cr3tP@ss"\ncd "/opt/app"\necho fin\n'));
      final cd = r.findings.firstWhere((f) => f.ruleId == 'ROB005');
      final fp = FalsePositive.of(cd, r, comment: ' volontaire ');
      expect(fp.context[fp.focus], 'cd "…"');
      expect(fp.context, contains(isNull)); // ligne 3 : secret, non recopiée
      expect(jsonEncode(fp.toJson()), isNot(contains('S3cr3t')));
      expect(fp.comment, 'volontaire');
      final log = FalsePositiveLog(File('${tmp.path}/fp.jsonl'));
      expect(await log.append(fp), 1);
      expect(await log.append(fp), 2);
      final cases = await log.read();
      expect(cases.first['rule'], 'ROB005');
      expect(cases.first['version'], appVersion);
    });
  });

  group('configuration Ruff du projet', () {
    test('recherche jusqu\'à la racine git ; arguments', () {
      Directory('${tmp.path}/.git').createSync();
      Directory('${tmp.path}/pkg/sub').createSync(recursive: true);
      File('${tmp.path}/pyproject.toml').writeAsStringSync(
          '[project]\nname = "x"\n\n[tool.ruff]\nline-length = 90\n');
      final script = '${tmp.path}/pkg/sub/s.py';
      expect(ruffProjectConfig(script), '${tmp.path}/pyproject.toml');
      File('${tmp.path}/pkg/ruff.toml').writeAsStringSync('line-length = 80\n');
      expect(ruffProjectConfig(script), '${tmp.path}/pkg/ruff.toml');

      const own = CheckConfig();
      expect(RuffAnalyzer.checkArgs(own, scriptPath: script),
          containsAll(['--isolated', startsWith('--select=')]));
      final proj = CheckConfig.parse('tools:\n  ruff:\n    config: project\n');
      final args = RuffAnalyzer.checkArgs(proj, scriptPath: script);
      expect(
          args, containsAllInOrder(['--config', '${tmp.path}/pkg/ruff.toml']));
      expect(args.any((a) => a.startsWith('--select')), isFalse);
      expect(args, isNot(contains('--isolated')));
      // Sans configuration de projet : réglages de check-script.
      expect(RuffAnalyzer.checkArgs(proj, scriptPath: '/nulle/part/x.py'),
          contains('--isolated'));
    });
  });

  group('tableau de bord', () {
    test('courbe SVG, dépôts, règles fréquentes', () async {
      final e = Engine(runner: noTools());
      final a =
          await e.analyze(script('#!/bin/bash\negrep a f\n', path: 'a.sh'));
      final b = await e.analyze(script('#!/bin/sh\necho b\n', path: 'b.sh'));
      final html = renderDashboard([
        DashboardRepo('alpha', '/r/alpha', [
          a
        ], [
          HistoryEntry.of('/r/alpha', [a], date: DateTime(2026)),
          HistoryEntry.of('/r/alpha', [a])
        ]),
        DashboardRepo('beta', '/r/beta', [
          b
        ], [
          HistoryEntry.of('/r/beta', [b])
        ]),
      ], Lang.fr);
      expect(html, contains('Tableau de bord — 2 dépôts'));
      expect(html, contains('>alpha</a>'));
      expect(html, contains('<svg class="spark"'));
      expect(html, contains('<code>POR005</code>'));
      expect(sparkline([5.0]), isEmpty);
    });

    test('CLI : --dashboard et --history-dir', () async {
      for (final r in ['r1', 'r2']) {
        Directory('${tmp.path}/$r').createSync();
        File('${tmp.path}/$r/s.sh').writeAsStringSync('#!/bin/sh\necho $r\n');
      }
      final hist = '${tmp.path}/hist';
      Future<int> run() => cli.run([
            '-q',
            '--history-dir',
            hist,
            '--dashboard',
            '${tmp.path}/d.html',
            '${tmp.path}/r1',
            '${tmp.path}/r2',
          ], out: IOSink(_Sink()), err: IOSink(_Sink()), runner: noTools());
      expect(await run(), 0);
      expect(await run(), 0);
      final html = File('${tmp.path}/d.html').readAsStringSync();
      expect(html, contains('>r1</a>'));
      expect(html, contains('>r2</a>'));
      final h = await FolderHistory(Directory(hist)).load('${tmp.path}/r1');
      expect(h, hasLength(2));
    });
  });
}
