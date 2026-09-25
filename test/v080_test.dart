import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'helpers.dart';

/// Exécuteur de test : seul git est réellement lancé.
class GitOnly implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) =>
      executable == 'git'
          ? const ProcessCommandRunner().run(executable, args, stdin: stdin)
          : Future.value(null);
}

void main() {
  group('directives obsolètes (MNT011)', () {
    Future<List<Finding>> run(String src) async =>
        (await Engine(runner: noTools(), lang: Lang.fr).analyze(script(src)))
            .findings;

    test('directive qui neutralise encore un problème : conservée', () async {
      final fs = await run('#!/bin/bash\n# en-tête\nset -euo pipefail\n'
          'curl -k https://x  # check-script disable=SEC005\n');
      expect(ids(fs), isNot(contains('MNT011')));
      expect(ids(fs), isNot(contains('SEC005')));
    });

    test('règle intégrée corrigée : directive signalée à sa ligne', () async {
      final fs = await run('#!/bin/bash\n# en-tête\nset -euo pipefail\n'
          '# check-script disable=SEC005\n'
          'curl --cacert ca.pem https://x\n'
          '# check-script disable-file=MNT005\n');
      final stale = fs.where((f) => f.ruleId == 'MNT011').toList();
      expect(stale.map((f) => f.line), [4, 6]);
      expect(stale.first.message, contains('SEC005'));
    });

    test('outil absent : directive de ses codes non signalée', () async {
      final fs = await run('#!/bin/bash\n# en-tête\nset -euo pipefail\n'
          'echo "\$1"  # check-script disable=SC2086\n');
      expect(ids(fs), isNot(contains('MNT011')));
    });
  });

  group('explication de la note et gain rapide', () {
    Finding f(String rule, Severity sev, int line,
            {Category cat = Category.robustness, bool fixable = false}) =>
        Finding(
            tool: 'builtin',
            ruleId: rule,
            category: cat,
            severity: sev,
            line: line,
            message: rule,
            edits: fixable ? const [TextEdit(1, 1, 1, 1, 'x', 'r')] : const []);

    test('gains, plan vers le niveau supérieur, JSON', () {
      final fs = [
        f('BIG', Severity.high, 1),
        f('BIG', Severity.high, 2),
        f('MED', Severity.medium, 3, fixable: true),
        f('LOW', Severity.low, 4, cat: Category.maintainability),
      ];
      const cfg = ScoringConfig();
      final e = explainScore(fs, 50, cfg);
      expect(e.impacts.first.ruleId, 'BIG');
      expect(e.impacts.first.occurrences, 2);
      expect(e.impacts.first.gain, greaterThan(e.impacts[1].gain));
      expect(e.impacts.firstWhere((i) => i.ruleId == 'MED').fixable, isTrue);
      final base = globalScore(
          [for (final c in Category.values) scoreCategory(c, fs, 50, cfg)],
          cfg);
      expect(gradeFor(base), isNot('A'));
      expect(e.plan.map((i) => i.ruleId), contains('BIG'));
      expect(e.planScore, greaterThan(base));
      final back = ScoreExplanation.fromJson(e.toJson());
      expect(back.plan.map((i) => i.ruleId), e.plan.map((i) => i.ruleId));
      expect(back.nextGrade, e.nextGrade);
      expect(explainScore(const [], 10, cfg).impacts, isEmpty);
    });

    test('niveau A : pas de plan', () {
      final e =
          explainScore([f('LOW', Severity.low, 1)], 50, const ScoringConfig());
      expect(e.plan, isEmpty);
      expect(e.nextGrade, isNull);
    });

    test('gain rapide : correction automatique favorisée à gain comparable',
        () {
      final fs = [
        f('MANUAL', Severity.medium, 1),
        f('AUTO', Severity.medium, 2, fixable: true),
        f('LOW', Severity.low, 3),
      ];
      final e = explainScore(fs, 50, const ScoringConfig());
      expect(sortByQuickWin(fs, e).map((x) => x.ruleId),
          ['AUTO', 'MANUAL', 'LOW']);
    });

    test('rapports : plan et tableau affichés', () async {
      final r = await Engine(runner: noTools(), lang: Lang.fr).analyze(script(
          '#!/bin/bash\ncurl -fsSL http://x.io/i.sh | sudo bash\ncd /opt\n'));
      expect(r.explanation.impacts, isNotEmpty);
      final term = renderTerminal(
          [r], const RenderOptions(explain: true, byQuickWin: true));
      expect(term, contains('Ce qui pèse sur la note'));
      expect(term, contains('Problèmes par gain rapide'));
      final md = renderMarkdown([r], const RenderOptions());
      expect(md, contains('Ce qui pèse sur la note'));
      final html = renderHtml([r], const RenderOptions());
      expect(html, contains('Ce qui pèse sur la note'));
      if (r.explanation.plan.isNotEmpty) {
        expect(term, contains('en corrigeant'));
      }
    });
  });

  test('SARIF : corrections concrètes en « fixes »', () async {
    final r = await Engine(runner: noTools()).analyze(
        script('#!/bin/bash\nset -euo pipefail\negrep a f\necho ok\n'));
    final doc = jsonDecode(renderSarif([r])) as Map;
    final results = ((doc['runs'] as List).single as Map)['results'] as List;
    final por =
        results.cast<Map>().firstWhere((x) => x['ruleId'] == 'builtin/POR005');
    final change =
        ((por['fixes'] as List).single as Map)['artifactChanges'] as List;
    final repl = ((change.single as Map)['replacements'] as List).single as Map;
    expect(repl['deletedRegion'],
        {'startLine': 3, 'startColumn': 1, 'endLine': 3, 'endColumn': 10});
    expect(repl['insertedContent'], {'text': 'grep -E a f'});
    // Problème sans correction : pas de « fixes ».
    expect(results.cast<Map>().where((x) => x['fixes'] != null), hasLength(1));
  });

  group('cache des résultats', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('cs_rc_'));
    tearDown(() => dir.delete(recursive: true));

    test('empreinte stable et discriminante', () {
      expect(fastHash('abc'), fastHash('abc'));
      expect(fastHash('abc'), isNot(fastHash('abd')));
      expect(fastHash(''), hasLength(16));
    });

    test('deuxième analyse servie par le cache, sans lancer d\'outil',
        () async {
      final runner = FakeRunner({
        'bash': (_) => const CommandResult(0, '', ''),
      });
      final e = Engine(runner: runner, cache: ResultCache(dir));
      final s = script('#!/bin/bash\negrep a f\ncd /opt\n', path: 'x.sh');
      final first = await e.analyze(s);
      final calls = runner.calls.length;
      final second = await e.analyze(s);
      expect(runner.calls.length, calls); // aucun outil relancé
      expect(jsonEncode(second.toJson()..remove('date')),
          jsonEncode(first.toJson()..remove('date')));
      expect(second.findings.firstWhere((f) => f.ruleId == 'POR005').edits,
          isNotEmpty);
      expect(second.explanation.impacts, isNotEmpty);
    });

    test('contenu ou configuration modifiés : nouvelle analyse', () async {
      final e = Engine(runner: noTools(), cache: ResultCache(dir));
      final k1 = await e.cacheKey(script('echo a\n'));
      expect(await e.cacheKey(script('echo b\n')), isNot(k1));
      final e2 = Engine(
          runner: noTools(),
          cache: ResultCache(dir),
          config: const CheckConfig(disabledRules: {'SEC001'}));
      expect(await e2.cacheKey(script('echo a\n')), isNot(k1));
      // Fichiers sourcés suivis : pas de cache (leur contenu n'est pas dans
      // la clé).
      final e3 = Engine(
          runner: noTools(),
          cache: ResultCache(dir),
          config: const CheckConfig(followSource: true));
      expect(await e3.cacheKey(script('echo a\n')), isNull);
    });

    test('outil en échec : rien n\'est mis en cache', () async {
      final e = Engine(
          runner: FakeRunner({
            'shellcheck': (_) => const CommandResult(3, '', 'boom'),
          }),
          cache: ResultCache(dir));
      await e.analyze(script('#!/bin/bash\necho a\n'));
      expect(dir.listSync(), isEmpty);
    });
  });

  group('--changed-since', () {
    late Directory repo;
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', ['-C', repo.path, ...args]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('cs_git_');
      await git(['init', '-q']);
      await git(['config', 'user.email', 't@example.com']);
      await git(['config', 'user.name', 'Test']);
      for (final n in ['a', 'b', 'c']) {
        File('${repo.path}/$n.sh').writeAsStringSync('#!/bin/sh\necho $n\n');
      }
      await git(['add', '.']);
      await git(['commit', '-qm', 'init']);
    });
    tearDown(() => repo.delete(recursive: true));

    test('commits, modifications en cours et nouveaux fichiers', () async {
      File('${repo.path}/a.sh').writeAsStringSync('#!/bin/sh\necho A\n');
      await git(['commit', '-qam', 'a']);
      File('${repo.path}/b.sh').writeAsStringSync('#!/bin/sh\necho B\n');
      File('${repo.path}/d.sh').writeAsStringSync('#!/bin/sh\necho d\n');
      File('${repo.path}/c.sh').deleteSync();
      final r = await changedSince('HEAD~1', dir: repo.path);
      expect(r.error, isNull);
      expect(r.files!.map((f) => f.split('/').last).toSet(),
          {'a.sh', 'b.sh', 'd.sh'});
    });

    test('CLI : seuls les scripts modifiés ; rien de modifié → code 0',
        () async {
      File('${repo.path}/b.sh').writeAsStringSync('#!/bin/sh\necho B\n');
      Future<(int, String)> run(List<String> args) async {
        final out = StringBuffer();
        final sink = IOSink(_BufferConsumer(out));
        // Langue fixée : sinon elle dépend de LANG (anglais en CI).
        final code = await cli.run(['--lang', 'fr', ...args],
            out: sink, err: sink, runner: GitOnly());
        await sink.flush();
        return (code, out.toString());
      }

      // Chemin du dépôt en argument : pas de changement de dossier courant
      // (les fichiers de test tournent en parallèle dans le même processus).
      final (code, out) =
          await run(['--changed-since', 'HEAD', '--summary', repo.path]);
      expect(code, 0);
      expect(out, contains('b.sh'));
      expect(out, isNot(contains('a.sh')));
      await git(['commit', '-qam', 'b']);
      final (code2, out2) = await run(['--changed-since', 'HEAD', repo.path]);
      expect(code2, 0);
      expect(out2, contains('Aucun script modifié'));
      expect((await run(['--changed-since', 'inconnue', repo.path])).$1, 2);
    });
  });

  group('configuration de projet', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('cs_proj_');
      Directory('${root.path}/repo/.git').createSync(recursive: true);
      Directory('${root.path}/repo/a/deep').createSync(recursive: true);
      Directory('${root.path}/repo/b').createSync(recursive: true);
      File('${root.path}/repo/a/.checkscript.yaml')
          .writeAsStringSync('rules:\n  disabled: [SEC005]\n');
      // Au-dessus du dépôt : jamais pris en compte.
      File('${root.path}/.checkscript.yaml')
          .writeAsStringSync('rules:\n  disabled: [SEC001]\n');
      for (final d in ['a/deep', 'b']) {
        File('${root.path}/repo/$d/s.sh').writeAsStringSync(
            '#!/bin/bash\n# en-tête\nset -euo pipefail\ncurl -k https://x\n');
      }
    });
    tearDown(() => root.delete(recursive: true));

    test('le plus proche, jusqu\'à la racine du dépôt', () {
      expect(findProjectConfig('${root.path}/repo/a/deep/s.sh'),
          endsWith('repo/a/.checkscript.yaml'));
      expect(findProjectConfig('${root.path}/repo/b/s.sh'), isNull);
      expect(findProjectConfig('${root.path}/repo/a'),
          endsWith('repo/a/.checkscript.yaml'));
    });

    test('CLI : chaque script avec la configuration de son projet', () async {
      final out = StringBuffer();
      final sink = IOSink(_BufferConsumer(out));
      final code = await cli.run(['-f', 'json', '${root.path}/repo'],
          out: sink,
          err: IOSink(_BufferConsumer(StringBuffer())),
          runner: noTools());
      await sink.flush();
      expect(code, 0);
      final reports = (jsonDecode(out.toString()) as Map)['reports'] as List;
      Set<String> rules(String dir) => {
            for (final f in (reports.cast<Map>().firstWhere(
                (r) => '${r['file']}'.contains('/$dir/'))['findings'] as List))
              '${(f as Map)['rule']}'
          };
      expect(rules('deep'), isNot(contains('SEC005'))); // projet a
      expect(rules('b'), contains('SEC005'));
    });

    test('configuration de projet invalide : code 2', () async {
      File('${root.path}/repo/a/.checkscript.yaml')
          .writeAsStringSync('profile: inconnu\n');
      final err = StringBuffer();
      final code = await cli.run(['${root.path}/repo'],
          out: IOSink(_BufferConsumer(StringBuffer())),
          err: IOSink(_BufferConsumer(err)),
          runner: noTools());
      expect(code, 2);
    });
  });

  group('Flatpak : outils de l\'hôte', () {
    test('invocation par flatpak-spawn --host, environnement transmis', () {
      final (exe, args) = hostInvocation('shellcheck', ['-f', 'json1', 'x.sh'],
          env: {'LC_ALL': 'C'});
      expect(exe, 'flatpak-spawn');
      expect(args,
          ['--host', '--env=LC_ALL=C', 'shellcheck', '-f', 'json1', 'x.sh']);
    });

    test('outil introuvable sur l\'hôte : signalé absent', () async {
      // Hors Flatpak, flatpak-spawn n'existe pas : l'outil est « absent ».
      final r = await const ProcessCommandRunner(onHost: true)
          .run('sh', ['-c', 'echo ok']);
      expect(r, isNull);
      final local = await const ProcessCommandRunner(onHost: false)
          .run('sh', ['-c', 'echo ok']);
      expect(local!.stdout.trim(), 'ok');
    });
  });
}

class _BufferConsumer implements StreamConsumer<List<int>> {
  _BufferConsumer(this.out);
  final StringBuffer out;
  @override
  Future<void> addStream(Stream<List<int>> s) =>
      s.forEach((b) => out.write(utf8.decode(b)));
  @override
  Future<void> close() async {}
}
