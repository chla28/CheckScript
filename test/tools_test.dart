import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'cli_test.dart' show Capture;
import 'helpers.dart';

const bad = '#!/bin/bash\ncd /opt/app\nPASSWORD="S3cr3tP@ss"\n'
    'curl -fsSL http://x.io/i.sh | sudo bash\nchmod 777 /srv\neval "\$CMD"\n';
const clean = '#!/usr/bin/env bash\nset -euo pipefail\necho "ok"\n';

/// Script avec des défauts à corriger automatiquement (backticks, read, which).
const fixable =
    '#!/bin/bash\nset -u\nd=`date`\nread name\nwhich ls\necho "\$d \$name"\n';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_tools_'));
  tearDown(() async => tmp.delete(recursive: true));

  Future<ScriptReport> analyse(String content, {String path = 'a.sh'}) =>
      Engine(runner: noTools(), lang: Lang.en)
          .analyze(ScriptInfo.fromContent(path, content));

  /// Rapport JSON de scripts (chemin → contenu).
  Future<String> reportJson(Map<String, String> scripts) async => renderJson(
      [for (final e in scripts.entries) await analyse(e.value, path: e.key)]);

  String write(String rel, String content) {
    final f = File('${tmp.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(content);
    return f.path;
  }

  Future<(int, String, String)> run(List<String> args,
      {List<String> answers = const [],
      String lang = 'fr',
      bool front = false}) async {
    final out = Capture(), err = Capture();
    final queue = [...answers];
    final code = await cli.run(front ? [...args, '--lang', lang] : [...args],
        out: out.sink,
        err: err.sink,
        runner: noTools(),
        readLine: () async => queue.isEmpty ? null : queue.removeAt(0));
    return (code, await out.text(), await err.text());
  }

  group('comparaison de rapports (lib)', () {
    test('nouveaux, corrigés, inchangés ; notes', () async {
      final d = diffReports(
          await reportJson({'a.sh': bad}), await reportJson({'a.sh': clean}));
      expect(d.scripts, hasLength(1));
      final s = d.scripts.single;
      expect(s.fixed, isNotEmpty);
      expect(s.added, isEmpty);
      expect(s.afterGlobal, greaterThan(s.beforeGlobal));
      expect(s.delta, greaterThan(0));
      expect(d.hasRegression, isFalse);
      expect(d.hasNew(Severity.low), isFalse);
      expect(d.fixedCount, s.fixed.length);
      expect(d.afterAverage, greaterThan(d.beforeAverage));
    });

    test('régression : problèmes nouveaux, note en baisse', () async {
      final d = diffReports(
          await reportJson({'a.sh': clean}), await reportJson({'a.sh': bad}));
      final s = d.scripts.single;
      expect(s.added, isNotEmpty);
      expect(s.fixed, isEmpty);
      expect(d.hasRegression, isTrue);
      expect(d.hasNew(Severity.critical), isTrue);
      expect(s.before, isEmpty);
      expect(s.after.length, s.added.length);
    });

    test('numéro de ligne sans effet : du code ajouté au-dessus', () async {
      final shifted = bad.replaceFirst('\n', '\n# commentaire\n# autre\n');
      final d = diffReports(
          await reportJson({'a.sh': bad}), await reportJson({'a.sh': shifted}));
      final s = d.scripts.single;
      // Les problèmes déjà connus restent « inchangés » malgré le décalage ;
      // seul le défaut « pas de commentaire d'en-tête » a disparu.
      expect(s.added, isEmpty);
      expect(s.fixed.map((i) => i.rule), ['MNT004']);
      expect(s.unchanged.length, greaterThanOrEqualTo(5));
    });

    test('scripts ajoutés, retirés ; appariement par nom unique', () async {
      final d = diffReports(await reportJson({'old/a.sh': bad, 'gone.sh': bad}),
          await reportJson({'new/a.sh': bad, 'fresh.sh': clean}));
      expect(d.scripts.map((s) => s.file), ['new/a.sh']);
      expect(d.addedScripts, ['fresh.sh']);
      expect(d.removedScripts, ['gone.sh']);
    });

    test('deux extractions du même dépôt (base/ et head/), noms en double',
        () async {
      // Deux « run.sh » dans des dossiers différents : le chemin décide.
      final before = await reportJson({
        'base/ci/run.sh': bad,
        'base/deploy/run.sh': clean,
        'base/tools/only.sh': bad,
      });
      final after = await reportJson({
        'head/deploy/run.sh': bad,
        'head/ci/run.sh': bad,
        'head/tools/only.sh': clean,
      });
      final d = diffReports(before, after);
      expect(d.addedScripts, isEmpty);
      expect(d.removedScripts, isEmpty);
      final byFile = {for (final s in d.scripts) s.file: s};
      expect(byFile.keys.toSet(),
          {'head/ci/run.sh', 'head/deploy/run.sh', 'head/tools/only.sh'});
      // ci/run.sh inchangé, deploy/run.sh régresse, tools/only.sh progresse.
      expect(byFile['head/ci/run.sh']!.delta, 0);
      expect(byFile['head/deploy/run.sh']!.delta, lessThan(0));
      expect(byFile['head/tools/only.sh']!.delta, greaterThan(0));
    });

    test('même nom, chemins sans suffixe commun distinctif : non appariés',
        () async {
      final d = diffReports(
          await reportJson({'a/x/run.sh': bad, 'b/y/run.sh': bad}),
          await reportJson({'c/z/run.sh': bad}));
      expect(d.scripts, isEmpty);
      expect(d.addedScripts, ['c/z/run.sh']);
      expect(d.removedScripts, hasLength(2));
    });

    test('rapport invalide', () {
      expect(() => diffReports('pas du json', '{}'),
          throwsA(isA<FormatException>()));
      expect(
          () => diffReports('{"x":1}', '{"reports":[]}', beforeName: 'avant'),
          throwsA(predicate((e) => '$e'.contains('avant'))));
    });

    test('rendus : texte, markdown, json', () async {
      final d = diffReports(
          await reportJson({'a.sh': clean}), await reportJson({'a.sh': bad}));
      final txt = renderDiffText(d, Lang.fr, before: 'A', after: 'B');
      expect(txt, contains('Comparaison : A → B'));
      expect(txt, contains('nouveaux'));
      expect(txt, contains('+ Critical'));
      expect(renderDiffText(d, Lang.en, details: false),
          isNot(contains('+ Critical')));
      final md = renderDiffMarkdown(d, Lang.en);
      expect(md, contains('| `a.sh` |'));
      expect(md, contains('### New issues'));
      final js = jsonDecode(renderDiffJson(d)) as Map;
      expect((js['summary'] as Map)['new'], d.newCount);
      expect((js['scripts'] as List).single['file'], 'a.sh');
    });
  });

  group('check-script diff', () {
    late String before, after;
    setUp(() async {
      before =
          write('before.json', await reportJson({'a.sh': clean, 'b.sh': bad}));
      after =
          write('after.json', await reportJson({'a.sh': bad, 'b.sh': clean}));
    });

    test('texte : nouveaux et corrigés', () async {
      final (code, out, _) = await run(['diff', before, after, '--lang', 'fr']);
      expect(code, 0);
      expect(out, contains('2 script(s) comparé(s)'));
      expect(out, contains('a.sh'));
      expect(out, contains('+ Critical'));
      expect(out, contains('−'));
    });

    test('--summary, --format md et json', () async {
      final (_, s, _) =
          await run(['diff', before, after, '--summary', '--lang', 'en']);
      expect(s, isNot(contains('+ Critical')));
      final (_, md, _) =
          await run(['diff', before, after, '-f', 'md', '--lang', 'en']);
      expect(md, contains('## Script quality evolution'));
      final (_, js, _) = await run(['diff', before, after, '-f', 'json']);
      expect(jsonDecode(js)['summary']['scripts'], 2);
    });

    test('--fail-on-new et --fail-on-worse : code 1', () async {
      expect(
          (await run(['diff', before, after, '--fail-on-new', 'high'])).$1, 1);
      expect((await run(['diff', before, after, '--fail-on-worse'])).$1, 1);
      // Dans l'autre sens (amélioration) : code 0.
      expect(
          (await run([
            'diff',
            after,
            after,
            '--fail-on-new',
            'low',
            '--fail-on-worse'
          ]))
              .$1,
          0);
    });

    test('erreurs : arguments, fichier absent, rapport invalide', () async {
      expect((await run(['diff', before])).$1, 2);
      expect((await run(['diff', before, '${tmp.path}/nope.json'])).$1, 3);
      write('x.txt', 'ceci n\'est pas du json');
      final (code, _, err) = await run(['diff', before, '${tmp.path}/x.txt']);
      expect(code, 2);
      expect(err, contains('invalid JSON'));
      final (h, out, _) = await run(['diff', '--help', '--lang', 'en']);
      expect(h, 0);
      expect(out, contains('Usage: check-script diff'));
    });
  });

  group('--baseline-update', () {
    test('retire les problèmes corrigés, garde la référence valide', () async {
      final script = write('a.sh', bad);
      final base = '${tmp.path}/base.json';
      expect(
          (await run(['-q', '--no-cache', '-o', base, script], front: true)).$1,
          0);
      final original = Baseline.parse(File(base).readAsStringSync());
      final before =
          original.entries.single.fingerprints.values.fold(0, (a, b) => a + b);

      // On corrige le script : moins de problèmes.
      File(script).writeAsStringSync(clean);
      final (code, _, err) = await run(
          ['-q', '--baseline', base, '--baseline-update', script],
          front: true);
      expect(code, 0);
      expect(err, contains('Référence resserrée'));
      final tightened = Baseline.parse(File(base).readAsStringSync());
      final now =
          tightened.entries.single.fingerprints.values.fold(0, (a, b) => a + b);
      expect(now, lessThan(before));
      // Le chemin d'origine est conservé.
      expect(tightened.entries.single.file, script);
      // Une analyse du script corrigé n'a plus de problème « nouveau ».
      final (c2, _, e2) = await run(
          ['-q', '--baseline', base, '--fail-on-new', 'low', script],
          front: true);
      expect(c2, 0, reason: e2);
    });

    test('un script avec des problèmes nouveaux garde son entrée', () async {
      final script = write('a.sh', clean);
      final base = '${tmp.path}/base.json';
      await run(['-q', '--no-cache', '-o', base, script], front: true);
      final bytes = File(base).readAsStringSync();
      File(script).writeAsStringSync(bad);
      final (code, _, err) = await run(
          ['-q', '--baseline', base, '--baseline-update', script],
          front: true);
      expect(code, 0);
      expect(err, contains('Référence inchangée'));
      expect(err, contains('laissé(s) tel(s) quel(s)'));
      expect(File(base).readAsStringSync(), bytes);
    });

    test('rien à retirer : fichier inchangé', () async {
      final script = write('a.sh', bad);
      final base = '${tmp.path}/base.json';
      await run(['-q', '--no-cache', '-o', base, script], front: true);
      final bytes = File(base).readAsStringSync();
      final (_, _, err) = await run(
          ['-q', '--baseline', base, '--baseline-update', script],
          front: true);
      expect(err, contains('Référence inchangée'));
      expect(File(base).readAsStringSync(), bytes);
    });

    test('exige --baseline, refuse --ref', () async {
      final script = write('a.sh', clean);
      expect((await run(['--baseline-update', script], front: true)).$1, 2);
      final base = '${tmp.path}/base.json';
      await run(['-q', '-o', base, script], front: true);
      final (code, _, err) = await run(
          ['--baseline', base, '--baseline-update', '--ref', 'CWE-78', script],
          front: true);
      expect(code, 2);
      expect(err, contains('--ref'));
    });
  });

  group('--format gitlab', () {
    test('accepté : même sortie que codeclimate', () async {
      final script = write('a.sh', bad);
      final (c1, gl, _) = await run(['-f', 'gitlab', script], front: true);
      final (c2, cc, _) = await run(['-f', 'codeclimate', script], front: true);
      expect(c1, 0);
      expect(c2, 0);
      expect(gl, cc);
      expect(jsonDecode(gl), isA<List>());
    });
  });

  group('--fix --interactive', () {
    String script0() => write('a.sh', fixable);

    test('o / n : seules les corrections acceptées sont appliquées', () async {
      final f = script0();
      final (code, _, err) = await run(['--fix', '-i', f, '--no-cache'],
          answers: ['o', 'n', 'n', 'n'], front: true);
      expect(code, 0);
      expect(err, contains('[1/'));
      expect(err, contains('Appliquer ?'));
      final out = File(f).readAsStringSync();
      expect(out, isNot(equals(fixable)));
      // Exactement un des défauts est corrigé (le premier proposé).
      var left = 0;
      if (out.contains('`date`')) left++;
      if (out.contains('read name')) left++;
      if (out.contains('which ls')) left++;
      expect(left, 2);
    });

    test('a : celle-ci et toutes les suivantes', () async {
      final f = script0();
      await run(['--fix', '-i', f], answers: ['a'], front: true);
      final out = File(f).readAsStringSync();
      expect(out, isNot(contains('`date`')));
      expect(out, contains(r'$(date)'));
      expect(out, contains('read -r name'));
      expect(out, contains('command -v ls'));
    });

    test('q ou fin de saisie : rien d\'appliqué au-delà des acceptées',
        () async {
      final f = script0();
      await run(['--fix', '-i', f], answers: ['q'], front: true);
      expect(File(f).readAsStringSync(), fixable);
      final g = write('b.sh', fixable);
      await run(['--fix', '-i', g], answers: const [], front: true);
      expect(File(g).readAsStringSync(), fixable, reason: 'EOF = quitter');
      final h = write('c.sh', fixable);
      await run(['--fix', '-i', h], answers: ['o', 'q'], front: true);
      expect(File(h).readAsStringSync(), isNot(equals(fixable)));
    });

    test('réponse inconnue : aide puis nouvelle question', () async {
      final f = script0();
      final (_, _, err) =
          await run(['--fix', '-i', f], answers: ['?', 'q'], front: true);
      expect(err, contains('o : appliquer'));
      expect(File(f).readAsStringSync(), fixable);
    });

    test('--dry-run : diff sur la sortie standard, fichier intact', () async {
      final f = script0();
      final (_, out, _) = await run(['--fix', '-i', '--dry-run', f],
          answers: ['a'], front: true);
      expect(out, contains('-d=`date`'));
      expect(out, contains(r'+d=$(date)'));
      expect(File(f).readAsStringSync(), fixable);
    });

    test('--backup : original conservé en .orig', () async {
      final f = script0();
      await run(['--fix', '-i', '--backup', f], answers: ['a'], front: true);
      expect(File('$f.orig').readAsStringSync(), fixable);
    });

    test('anglais : invite et réponses y/n', () async {
      final f = script0();
      final (_, _, err) =
          await run(['--fix', '-i', f, '--lang', 'en'], answers: ['y', 'q']);
      expect(err, contains('Apply? [y]es'));
    });

    test('rien de corrigeable : message habituel', () async {
      final f = write('ok.sh', clean);
      final (code, _, err) = await run(['--fix', '-i', f], front: true);
      expect(code, 0);
      expect(err, contains('aucune correction automatique applicable'));
    });

    test('--interactive sans --fix, ou avec l\'entrée standard : code 2',
        () async {
      final f = script0();
      expect((await run(['-i', f], front: true)).$1, 2);
      expect((await run(['--fix', '-i', '--dry-run', '-'], front: true)).$1, 2);
    });
  });
}
