import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Finding _f(String rule, int line,
        {String tool = 'builtin',
        int? endLine,
        List<String> equivalents = const [],
        Category category = Category.robustness}) =>
    Finding(
        tool: tool,
        ruleId: rule,
        category: category,
        severity: Severity.low,
        line: line,
        endLine: endLine,
        message: rule,
        equivalents: equivalents);

void main() {
  group('règles désactivées transmises aux outils', () {
    test('même règle dans un autre outil', () {
      expect(sameRuleIds('S602'), {'B602'});
      expect(sameRuleIds('b602'), {'S602'});
      expect(sameRuleIds('PLW0602'), {'W0602'});
      expect(sameRuleIds('W0702'), containsAll(['E722', 'PLW0702']));
      expect(sameRuleIds('SC2164'), {'ROB005'});
      expect(sameRuleIds('POR005'), {'SC2196', 'SC2197'});
      expect(sameRuleIds('SEC022'), isEmpty);
    });

    test('exclusions : seulement les codes que l\'outil accepte', () {
      final c = const CheckConfig(disabledRules: {'ROB005', 'SEC001', 'B602'});
      expect(c.excludedFor('shellcheck'), containsAll(['SC1091', 'SC2164']));
      expect(c.excludedFor('shellcheck'), isNot(contains('SEC001')));
      expect(c.excludedFor('bandit'), containsAll(['B404', 'B603', 'B602']));
      // Ruff, mypy : un code inconnu les ferait échouer.
      expect(c.excludedFor('ruff'), const CheckConfig().tool('ruff').exclude);
      expect(c.isRuleDisabled('S602'), isTrue);
      expect(c.isRuleDisabled('sc2164'), isTrue);
      expect(c.isRuleDisabled('SC2086'), isFalse);
    });

    test('la même règle est masquée, pas une détection voisine', () {
      final out = applyConfig([
        _f('S602', 3, tool: 'ruff'),
        _f('subprocess-shell-true', 3,
            tool: 'semgrep', equivalents: const ['B6*']),
      ], const CheckConfig(disabledRules: {'B602'}));
      expect(out.map((f) => f.ruleId), ['subprocess-shell-true']);
    });

    test('--fix ne corrige pas une règle désactivée', () async {
      final runner = FakeRunner({
        'shfmt': (_) => const CommandResult(0, 'reformaté\n', ''),
      });
      final r = await fixScript(script('#!/bin/bash\negrep a f   \n'),
          config: const CheckConfig(disabledRules: {'MNT010', 'FORMAT'}),
          runner: runner);
      expect(r.fixed, '#!/bin/bash\ngrep -E a f   \n');
      expect(r.applied, {'POR005': 1});
      expect(runner.calls.map((c) => c.$1), isNot(contains('shfmt')));
    });

    test('--fix Python : --fixable limité aux codes actifs', () async {
      final runner = FakeRunner({
        'ruff': (a) => a.contains('--fix')
            ? const CommandResult(0, 'import os\nimport sys\n', '')
            : a.first == 'format'
                ? const CommandResult(0, 'import os\nimport sys\n', '')
                : const CommandResult(
                    1,
                    '[{"code":"E401","message":"m","location":{"row":1,"column":1},'
                        '"end_location":{"row":1,"column":15},"url":null,'
                        '"fix":{"applicability":"safe","edits":[{"content":"import os\\nimport sys",'
                        '"location":{"row":1,"column":1},"end_location":{"row":1,"column":15}}]}},'
                        '{"code":"I001","message":"m","location":{"row":1,"column":1},'
                        '"end_location":{"row":1,"column":15},"url":null,'
                        '"fix":{"applicability":"safe","edits":[{"content":"x",'
                        '"location":{"row":1,"column":1},"end_location":{"row":1,"column":2}}]}}]',
                    ''),
      });
      final r = await fixScript(script('import os, sys\n', path: 'f.py'),
          config: const CheckConfig(disabledRules: {'I001'}), runner: runner);
      expect(r.applied, {'E401': 1});
      final fix = runner.calls.firstWhere((c) => c.$2.contains('--fix'));
      expect(fix.$2, contains('--fixable=E401'));
    });
  });

  group('doublons sur plusieurs lignes', () {
    test('lignes qui se recouvrent, étendue plafonnée', () {
      final bandit = _f('B607', 46,
          tool: 'bandit', endLine: 49, equivalents: const ['S607']);
      expect(isDuplicate(bandit, _f('S607', 47, tool: 'ruff')), isTrue);
      expect(isDuplicate(bandit, _f('S607', 51, tool: 'ruff')), isFalse);
      // Règle couvrant 30 lignes : seule sa première ligne compte.
      final wide =
          _f('x', 10, tool: 'semgrep', endLine: 40, equivalents: const ['S6*']);
      expect(isDuplicate(wide, _f('S602', 20, tool: 'ruff')), isFalse);
      expect(isDuplicate(wide, _f('S602', 10, tool: 'ruff')), isTrue);
      // Même outil : même ligne exigée.
      expect(isDuplicate(_f('A', 1, endLine: 3), _f('A', 2)), isFalse);
    });

    test('bad.py réel : B607 (ligne 46) et S607 (ligne 47) fusionnés', () {
      final bandit = parseBandit(readFixture('outputs/python/bandit_bad.json'));
      final b607 = bandit.firstWhere((f) => f.ruleId == 'B607');
      expect((b607.line, b607.endLine), (46, 49));
      final ruff = parseRuff(readFixture('outputs/python/ruff_bad.json'));
      final kept = deduplicate([...bandit, ...ruff]);
      expect(kept.where((f) => f.ruleId.endsWith('607')).map((f) => f.ruleId),
          ['B607']);
    });
  });

  group('directives Python # noqa / # nosec', () {
    final lines = [
      'import os  # noqa',
      'x = eval(s)  # noqa: S307',
      'subprocess.call(c, shell=True)  # nosec',
      'subprocess.call(c, shell=True)  # nosec B602',
      'print(1)',
    ];
    final sup = Suppressions.parse(lines, python: true);
    Finding f(String rule, int line, {Category c = Category.robustness}) =>
        _f(rule, line, category: c);

    test('noqa : toute la ligne, ou les codes et la même règle ailleurs', () {
      expect(sup.suppresses(f('F401', 1)), isTrue);
      expect(sup.suppresses(f('B105', 1)), isTrue);
      expect(sup.suppresses(f('S307', 2)), isTrue);
      expect(sup.suppresses(f('B307', 2)), isTrue); // Bandit, même règle
      expect(sup.suppresses(f('W0123', 2)), isTrue); // Pylint, même règle
      expect(sup.suppresses(f('F841', 2)), isFalse);
    });

    test('nosec : sécurité de la ligne, ou le code indiqué', () {
      expect(sup.suppresses(f('B602', 3, c: Category.security)), isTrue);
      expect(
          sup.suppresses(f('subprocess-shell-true', 3, c: Category.security)),
          isTrue);
      expect(sup.suppresses(f('PYROB001', 3)), isFalse); // pas de la sécurité
      expect(sup.suppresses(f('S602', 4, c: Category.security)), isTrue);
      expect(sup.suppresses(f('B607', 4, c: Category.security)), isFalse);
      expect(sup.suppresses(f('F401', 5)), isFalse);
    });

    test('ignorées dans un script shell', () {
      final sh = Suppressions.parse(['echo a  # noqa'], python: false);
      expect(sh.suppresses(f('SC2086', 1)), isFalse);
    });
  });

  group('analyses en parallèle', () {
    test('mêmes résultats qu\'en séquentiel', () async {
      final s = script(readFixture('bad.sh'));
      final seq = await Engine(runner: noTools(), parallel: false).analyze(s);
      final par = await Engine(runner: noTools()).analyze(s);
      expect(par.tools.map((t) => t.tool), seq.tools.map((t) => t.tool));
      expect(par.findings.map((f) => '${f.ruleId}@${f.line}'),
          seq.findings.map((f) => '${f.ruleId}@${f.line}'));
      expect(par.global, seq.global);
    });

    test('dossier : ordre conservé, fichiers illisibles ignorés', () async {
      final d = await Directory.systemTemp.createTemp('cs_jobs_');
      addTearDown(() => d.delete(recursive: true));
      final paths = [
        for (var i = 0; i < 6; i++)
          (File('${d.path}/s$i.sh')..writeAsStringSync('#!/bin/sh\necho $i\n'))
              .path,
      ];
      File(paths[3]).writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3]);
      final skipped = <String>[];
      final done = <int>[];
      final reports = await Engine(runner: noTools()).analyzeFiles(paths,
          jobs: 3,
          onSkip: (p, _) => skipped.add(p),
          onDone: (n, total, _) => done.add(n));
      expect(reports.map((r) => r.script.path), [
        for (final p in paths)
          if (p != paths[3]) p
      ]);
      expect(skipped, [paths[3]]);
      expect(done, [1, 2, 3, 4, 5, 6]);
    });
  });

  group('Semgrep hors ligne', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('cs_sg_'));
    tearDown(() => dir.delete(recursive: true));
    const tc = ToolConfig(executable: 'semgrep');

    test('téléchargé une fois, puis servi par le cache', () async {
      var calls = 0;
      Future<String?> fetch(Uri u) async {
        calls++;
        expect(u.toString(), 'https://semgrep.dev/c/p/python');
        return 'rules:\n- id: x\n';
      }

      final (rules, label) =
          await SemgrepAnalyzer(fetch: fetch, cacheDir: dir).resolveRules(tc);
      expect(File(rules).readAsStringSync(), startsWith('rules:'));
      expect(label, 'p/python');
      final (again, label2) =
          await SemgrepAnalyzer(fetch: fetch, cacheDir: dir).resolveRules(tc);
      expect((again, label2), (rules, 'p/python (cache)'));
      expect(calls, 1);
      // Réponse JSON du registre : acceptée aussi.
      final json = await Directory.systemTemp.createTemp('cs_sg_json_');
      addTearDown(() => json.delete(recursive: true));
      final (r, _) = await SemgrepAnalyzer(
              fetch: (_) async => '{"rules":[{"id":"x"}]}', cacheDir: json)
          .resolveRules(tc);
      expect(File(r).readAsStringSync(), startsWith('{"rules"'));
    });

    test('hors ligne : cache ancien, sinon registre', () async {
      Future<String?> offline(Uri _) async => null;
      final (r1, _) =
          await SemgrepAnalyzer(fetch: offline, cacheDir: dir).resolveRules(tc);
      expect(r1, 'p/python');
      final cache = File('${dir.path}/semgrep-p-python.yaml')
        ..writeAsStringSync('rules: []\n')
        ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 30)));
      final (r2, l2) =
          await SemgrepAnalyzer(fetch: offline, cacheDir: dir).resolveRules(tc);
      expect((r2, l2), (cache.path, 'p/python (cache ancien)'));
      // Réponse qui n'est pas un fichier de règles : ignorée.
      final (r3, _) =
          await SemgrepAnalyzer(fetch: (_) async => '<html>', cacheDir: dir)
              .resolveRules(tc);
      expect(r3, cache.path);
    });

    test('règles locales de la configuration', () async {
      final c = CheckConfig.parse(
          'tools:\n  semgrep:\n    config: /opt/regles/python.yml\n');
      expect(c.tool('semgrep').config, '/opt/regles/python.yml');
      final (rules, label) = await SemgrepAnalyzer(
              fetch: (_) => fail('pas de téléchargement'), cacheDir: dir)
          .resolveRules(c.tool('semgrep'));
      expect(
          (rules, label), ('/opt/regles/python.yml', '/opt/regles/python.yml'));
    });
  });

  group('export de la configuration en YAML', () {
    String describe(CheckConfig c) => [
          c.profile.name,
          [for (final x in c.contexts) x.name].join(','),
          c.followSource,
          c.pythonTarget,
          for (final n
              in {...CheckConfig.defaultTools.keys, ...c.tools.keys}.toList()
                ..sort())
            '$n=${c.tool(n).enabled}/${c.tool(n).executable}/'
                '${c.tool(n).exclude.join(',')}/${c.tool(n).config}',
          (c.disabledRules.toList()..sort()).join(','),
          [
            for (final e in c.overrides.entries)
              '${e.key}:${e.value.category}/${e.value.severity}'
          ].join(','),
          c.scoring.weights,
          c.scoring.categoryWeights,
          c.scoring.referenceLines,
          c.thresholds.maxLineLength,
          c.thresholds.maxFunctionLines,
          c.thresholds.maxNesting,
          c.thresholds.maxLinesWithoutFunction,
        ].join(' | ');

    test('aller-retour complet', () {
      final c = CheckConfig.parse('''
profile: legacy
context: [root, cron]
followSource: true
pythonTarget: "3.11"
tools:
  shellcheck: { path: "/opt/sc bin/shellcheck", exclude: [SC1091, SC2034] }
  bashate: false
  pylint: true
  semgrep: { config: /opt/regles.yml }
rules:
  disabled: [MNT005, "invalid-syntax", B602]
  overrides:
    SC2086: { category: security, severity: medium }
scoring:
  weights: { critical: 5, high: 2.5 }
  referenceLines: 80
  categoryWeights: { performance: 0.25 }
thresholds:
  maxLineLength: 110
''');
      final y = c.toYaml(header: 'Exporté par check-script');
      expect(y, startsWith('# Exporté par check-script\n'));
      expect(describe(CheckConfig.parse(y)), describe(c));
      // Les règles propres au profil legacy ne sont pas recopiées.
      expect(y, isNot(contains('MNT001')));
    });

    test('configuration par défaut : fichier minimal', () {
      final y = const CheckConfig().toYaml();
      expect(y.trim(), 'profile: default');
      expect(describe(CheckConfig.parse(y)), describe(const CheckConfig()));
    });
  });

  group('rapport HTML de dossier', () {
    test('synthèse, tableau triable, règles les plus fréquentes', () async {
      final e = Engine(runner: noTools(), lang: Lang.fr);
      final a = await e
          .analyze(script('#!/bin/bash\negrep a f\negrep b g\n', path: 'a.sh'));
      final b =
          await e.analyze(script('#!/bin/bash\negrep c h\n', path: 'b.sh'));
      final html = renderHtml([a, b], const RenderOptions(lang: Lang.fr));
      expect(html, contains('id="summary"'));
      expect(html, contains('2 scripts (2 shell, 0 Python)'));
      expect(html, contains('table class="sortable"'));
      expect(html, contains('Règles les plus fréquentes'));
      // POR005 : 3 occurrences dans 2 scripts, avant les règles plus rares.
      final top = html.substring(html.indexOf('Règles les plus fréquentes'));
      final row = RegExp(r'<code>POR005</code>.*?data-v="(\d+)">\d+</td>'
              r'<td class="n" data-v="(\d+)">')
          .firstMatch(top);
      expect(row, isNotNull);
      expect((row![1], row[2]), ('3', '2'));
      expect(html, contains('href="#summary"'));
    });

    test('un seul script : pas de synthèse de dossier', () async {
      final r = await Engine(runner: noTools())
          .analyze(script('#!/bin/sh\necho a\n'));
      final html = renderHtml([r], const RenderOptions());
      expect(html, isNot(contains('id="summary"')));
    });
  });

  group('calibrage Python', () {
    test('secret réel ou valeur d\'exemple', () {
      expect(looksLikeRealSecret('Prod-P4ssw0rd!2024'), isTrue);
      expect(looksLikeRealSecret('admin123'), isTrue);
      for (final v in [
        'changeme',
        'password1',
        '\${DB_PASS}',
        '<secret>',
        'xxxxxxxx',
        'short',
        'deux mots de passe'
      ]) {
        expect(looksLikeRealSecret(v), isFalse, reason: v);
      }
      Finding one(String value) => parseBandit('{"results":[{"test_id":"B105",'
              '"issue_severity":"LOW","issue_confidence":"MEDIUM",'
              '"issue_text":"Possible hardcoded password: \'$value\'",'
              '"line_number":3}]}')
          .single;
      expect(one('Prod-P4ssw0rd!2024').severity, Severity.critical);
      expect(one('changeme').severity, Severity.high);
      expect(one('changeme').message, isNot(contains('changeme')));
    });

    test('docstrings comptées comme documentation', () {
      final s = script(
          '#!/usr/bin/env python3\n"""Doc\n\nsur 3 lignes."""\n# c\nimport os\n\n'
          'def f():\n    """Une ligne."""\n    x = """a\nb"""\n    return x\n',
          path: 'a.py');
      expect((s.codeLines, s.commentLines), (5, 5));
    });

    test('PYROB003 (cron sans verrou) et PYROB004 (code de retour perdu)', () {
      const src = 'import sys\n\n\ndef main():\n    return 1\n\n\n'
          'if __name__ == "__main__":\n    main()\n';
      const facts = PythonFacts(ignoredExit: [9], functions: 1);
      final s = script(src, path: 'j.py');
      final plain =
          runPythonRules(s, const CheckConfig(), Lang.fr, facts: facts);
      expect(ids(plain), contains('PYROB004'));
      expect(ids(plain), isNot(contains('PYROB003'))); // hors cron
      final cron = runPythonRules(
          s, const CheckConfig(contexts: {ExecContext.cron}), Lang.fr,
          facts: facts);
      expect(ids(cron), contains('PYROB003'));
      final locked = runPythonRules(
          script('import fcntl\nfcntl.flock(f, fcntl.LOCK_EX)\n', path: 'l.py'),
          const CheckConfig(contexts: {ExecContext.cron}),
          Lang.fr);
      expect(ids(locked), isNot(contains('PYROB003')));
    });

    test('PYROB004 réel : main() sous la garde, sans sys.exit', () async {
      final s = script(
          'import sys\n\n\ndef main():\n    def inner():\n        return 2\n'
          '    inner()\n\n\ndef helper():\n    return None\n\n\n'
          'helper()\nif __name__ == "__main__":\n    main()\n    sys.exit(main())\n',
          path: 'k.py');
      final d = await Directory.systemTemp.createTemp('cs_py4_');
      addTearDown(() => d.delete(recursive: true));
      final f = File('${d.path}/k.py')..writeAsStringSync(s.content);
      final facts = await loadPythonFacts(AnalysisContext(
          script: s,
          filePath: f.path,
          config: const CheckConfig(),
          lang: Lang.fr,
          runner: const ProcessCommandRunner()));
      // main() ne renvoie de valeur que par la fonction imbriquée : ignoré ;
      // helper() renvoie None : ignoré.
      expect(facts?.ignoredExit, isEmpty);
    });
  });
}
