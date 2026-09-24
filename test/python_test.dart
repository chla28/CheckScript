import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String py(String name) => readFixture('outputs/python/$name');

bool _hasPython() {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Faux outils Python renvoyant les sorties capturées sur bad.py.
FakeRunner pythonTools() => FakeRunner({
      'ruff': (a) => a.contains('--version')
          ? const CommandResult(0, 'ruff 0.16.8', '')
          : a.first == 'format'
              ? CommandResult(1, py('ruff_format_bad.diff'), '')
              : CommandResult(1, py('ruff_bad.json'), ''),
      'bandit': (a) => a.contains('--version')
          ? const CommandResult(0, 'bandit 1.9.4', '')
          : CommandResult(1, py('bandit_bad.json'), ''),
      'semgrep': (a) => a.contains('--version')
          ? const CommandResult(0, '1.178.0', '')
          : CommandResult(0, py('semgrep_bad.json'), ''),
      'mypy': (a) => a.contains('--version')
          ? const CommandResult(0, 'mypy 2.3.1', '')
          : CommandResult(1, py('mypy_bad.jsonl'), ''),
      'radon': (a) => a.contains('--version')
          ? const CommandResult(0, '6.0.1', '')
          : a.first == 'cc'
              ? CommandResult(0, py('radon_cc_bad.json'), '')
              : CommandResult(0, py('radon_mi_bad.json'), ''),
      'vermin': (a) => a.contains('--version')
          ? const CommandResult(0, '1.8.0', '')
          : CommandResult(1, py('vermin_bad.txt'), ''),
    });

void main() {
  group('parseurs (sorties réelles sur bad.py)', () {
    test('Ruff : classement, équivalents, corrections sûres seulement', () {
      final fs = parseRuff(py('ruff_bad.json'));
      Finding rule(String id) => fs.firstWhere((f) => f.ruleId == id);
      expect(rule('S602').category, Category.security);
      expect(rule('S602').equivalents, contains('B602'));
      expect(rule('E722').severity, Severity.medium);
      expect(rule('E401').edits, isNotEmpty); // correction « safe »
      expect(rule('B006').edits, isEmpty); // correction « unsafe » écartée
      expect(rule('S105').equivalents, containsAll(['B105', 'PYSEC001']));
      // match refusé en 3.9 : portabilité, pas erreur de syntaxe.
      final m = rule('invalid-syntax');
      expect((m.category, m.severity), (Category.portability, Severity.high));
      expect(m.equivalents, contains('VERMIN'));
      expect(rule('E401').url, startsWith('https://docs.astral.sh/ruff/'));
    });

    test('Ruff : erreur de syntaxe réelle et famille par défaut', () {
      final fs = parseRuff('[{"code":null,"message":"Expected `)`",'
          '"location":{"row":1,"column":7},"end_location":{"row":1,"column":8},'
          '"fix":null,"url":null}]');
      expect(fs.single.ruleId, 'invalid-syntax');
      expect(fs.single.severity, Severity.critical);
      expect(fs.single.equivalents, contains('SYNTAX'));
      expect(classifyRuff('PERF401'), (Category.performance, Severity.low));
      expect(classifyRuff('PLE1142'), (Category.robustness, Severity.high));
      expect(parseRuff(''), isEmpty);
      expect(() => parseRuff('{}'), throwsFormatException);
    });

    test('Bandit : secret jamais recopié, reclassements, équivalents', () {
      final fs = parseBandit(py('bandit_bad.json'));
      final secret = fs.firstWhere((f) => f.ruleId == 'B105');
      expect(secret.message, isNot(contains('S3cr3t')));
      expect(secret.severity, Severity.high);
      expect(fs.firstWhere((f) => f.ruleId == 'B602').equivalents,
          contains('S602'));
      expect(fs.firstWhere((f) => f.ruleId == 'B110').category,
          Category.robustness);
      expect(fs.firstWhere((f) => f.ruleId == 'B602').column, greaterThan(0));
    });

    test('Semgrep : résultat, correction, secret masqué, erreurs', () {
      final (fs, errors) = parseSemgrep(py('semgrep_bad.json'));
      expect(errors, isEmpty);
      final f = fs.single;
      expect(f.ruleId, 'subprocess-shell-true');
      expect(f.category, Category.security);
      expect(f.line, 8);
      expect(f.edits, isNotEmpty);
      final (secret, _) = parseSemgrep('{"results":[{"check_id":'
          '"python.x.hardcoded-password","start":{"line":2,"col":1},'
          '"end":{"line":2,"col":9},"extra":{"message":"password is \'hunter2\'",'
          '"severity":"ERROR","fix":"x","metadata":{"category":"security"}}}],'
          '"errors":[]}');
      expect(secret.single.message, isNot(contains('hunter2')));
      expect(secret.single.edits, isEmpty);
      final (none, errs) = parseSemgrep(
          '{"results":[],"errors":[{"message":"Failed to download config"}]}');
      expect(none, isEmpty);
      expect(errs.single, contains('download'));
    });

    test('mypy : un objet par ligne, notes ignorées', () {
      final fs = parseMypy('${py('mypy_bad.jsonl')}\n'
          '{"line": 19, "message": "See docs", "code": null, "severity": "note"}');
      expect(fs.map((f) => f.ruleId), ['arg-type', 'operator']);
      expect(fs.first.category, Category.robustness);
      expect(fs.first.url, endsWith('#code-arg-type'));
    });

    test('Pyright : positions 0-based, version de Python', () {
      final fs = parsePyright(py('pyright_bad.json'));
      final op = fs.firstWhere((f) => f.ruleId == 'reportOperatorIssue');
      expect(op.line, 19);
      final v = fs.firstWhere((f) => f.ruleId == 'PYRIGHT');
      expect((v.category, v.line), (Category.portability, 50));
    });

    test('Pylint : types, reclassements, équivalents Ruff', () {
      final fs = parsePylint(py('pylint_bad.json'));
      Finding rule(String id) => fs.firstWhere((f) => f.ruleId == id);
      expect(rule('W0123').category, Category.security);
      expect(rule('W0102').severity, Severity.medium);
      expect(rule('C0410').equivalents, contains('E401'));
      expect(rule('W0102').equivalents, containsAll(['PLW0102', 'B006']));
      expect(rule('C0200').category, Category.maintainability);
    });

    test('Radon : complexité ≥ 11, indice de maintenabilité', () {
      final cc = parseRadonCc(py('radon_cc_bad.json'));
      expect(cc.single.line, 22);
      expect(cc.single.message, contains('classify'));
      expect(cc.single.severity, Severity.low);
      expect(parseRadonMi(py('radon_mi_bad.json')), isEmpty); // rang A
      expect(parseRadonMi('{"f.py": {"mi": 7.5, "rank": "C"}}').single.severity,
          Severity.medium);
      expect(parseRadonCc('{"f.py": {"error": "invalid syntax"}}'), isEmpty);
    });

    test('Vermin : fonctionnalités au-delà de la cible', () {
      final fs = parseVermin(py('vermin_bad.txt'), '3.9');
      expect(fs.single.line, 50);
      expect(fs.single.message, contains('3.10'));
      expect(fs.single.category, Category.portability);
    });

    test('syntaxe Python : ligne:colonne:message', () {
      final f = parsePythonSyntaxError('3:7:invalid syntax\n').single;
      expect((f.line, f.column, f.severity), (3, 7, Severity.critical));
      expect(parsePythonSyntaxError(''), isEmpty);
    });
  });

  group('moteur', () {
    test('outils du langage seulement', () {
      final e = Engine(runner: noTools());
      final names = [
        for (final a in e.analyzersFor(script('x = 1\n', path: 'a.py'))) a.name
      ];
      expect(names,
          containsAll(['ruff', 'bandit', 'syntax', 'builtin', 'gitleaks']));
      expect(names, isNot(contains('shellcheck')));
      final sh = [
        for (final a in e.analyzersFor(script('#!/bin/sh\n'))) a.name
      ];
      expect(sh, contains('shellcheck'));
      expect(sh, isNot(contains('ruff')));
    });

    test('bad.py : dédoublonnage entre outils, secret masqué', () async {
      final e = Engine(runner: pythonTools(), lang: Lang.en);
      final r = await e.analyze(
          ScriptInfo.fromContent('bad.py', readFixture('bad.py')),
          filePath: fixture('bad.py'));
      expect(r.tools.map((t) => t.tool), isNot(contains('shellcheck')));
      expect(r.tools.firstWhere((t) => t.tool == 'pylint').status,
          ToolStatus.disabled);
      final at8 = r.findings
          .where((f) => f.line == 8 && f.category == Category.security);
      // Bandit B602, Ruff S602 et Semgrep subprocess-shell-true : un seul.
      expect(at8.map((f) => f.ruleId), ['B602']);
      final secret = r.findings.where((f) => f.line == 4).toList();
      expect(secret, isNotEmpty);
      expect(secret.every((f) => f.snippet == null && f.edits.isEmpty), isTrue);
      expect(secret.every((f) => !f.message.contains('S3cr3t')), isTrue);
      expect(ids(r.findings), containsAll(['E722', 'CC', 'PYPOR001']));
      // match : une seule détection de portabilité (Ruff, Vermin).
      expect(r.findings.where((f) => f.line == 50).length, 1);
    });
  });

  group('règles intégrées Python', () {
    final bad = ScriptInfo.fromContent('bad.py', readFixture('bad.py'));

    test('sans interpréteur : découpage ligne à ligne', () {
      final fs = runPythonRules(bad, const CheckConfig(), Lang.fr);
      expect(ids(fs),
          containsAll(['PYPOR001', 'PYMNT001', 'PYMNT002', 'PYROB001']));
      expect(fs.firstWhere((f) => f.ruleId == 'PYROB001').line, 8);
      // input() n'est signalé que sans terminal.
      expect(ids(fs), isNot(contains('PYROB002')));
      final cron = runPythonRules(
          bad, const CheckConfig(contexts: {ExecContext.cron}), Lang.fr);
      expect(cron.firstWhere((f) => f.ruleId == 'PYROB002').line, 9);
    });

    test('script propre : aucune règle', () {
      final good = ScriptInfo.fromContent('good.py', readFixture('good.py'));
      expect(runPythonRules(good, const CheckConfig(), Lang.fr), isEmpty);
    });

    test('secret à forte entropie : ligne masquée', () {
      final s = script(
          '#!/usr/bin/env python3\nKEY = "aZ3kQ9mW2xV7pL4nR8tY6uB1"\n',
          path: 'k.py');
      final f = runPythonRules(s, const CheckConfig(), Lang.en)
          .firstWhere((f) => f.ruleId == 'PYSEC001');
      expect(f.snippet, isNull);
    });

    test('arbre syntaxique réel : appels multi-lignes, alias d\'import',
        () async {
      final ctx = AnalysisContext(
          script: bad,
          filePath: fixture('bad.py'),
          config: const CheckConfig(),
          lang: Lang.fr,
          runner: const ProcessCommandRunner());
      final facts = await loadPythonFacts(ctx);
      expect(facts, isNotNull);
      expect(facts!.noTimeout, [8, 46]);
      expect(facts.inputs, [9]);
      expect(facts.mainGuard, isFalse);
      expect(facts.docstring, isFalse);
      final r = await BuiltinAnalyzer().analyze(ctx);
      expect(r.run.detail, 'ast');
    }, skip: _hasPython() ? null : 'python3 absent');
  });

  group('correction (--fix)', () {
    test('corrections sûres de Ruff puis formatage', () async {
      final runner = FakeRunner({
        'ruff': (a) => a.first == 'format'
            ? const CommandResult(
                0, 'import os\nimport subprocess\n\nx = 1\n', '')
            : a.contains('--fix')
                ? const CommandResult(
                    0, 'import os\nimport subprocess\nx = 1\n', '')
                : CommandResult(1, py('ruff_bad.json'), ''),
      });
      final r = await fixScript(
          script('import os, subprocess\nx = 1\n', path: 'f.py'),
          runner: runner);
      expect(r.applied, {'E401': 1, 'FORMAT': 1});
      expect(r.fixed, 'import os\nimport subprocess\n\nx = 1\n');
      // Pas de corrections shell sur un script Python.
      expect(runner.calls.map((c) => c.$1), isNot(contains('shellcheck')));
    });

    test('ruff désactivé : aucune correction', () async {
      final r = await fixScript(script('import os, sys\n', path: 'f.py'),
          config: const CheckConfig().withToolsDisabled(['ruff']),
          runner: noTools());
      expect(r.changed, isFalse);
    });
  });

  group('configuration et découverte', () {
    test('pythonTarget : chaîne obligatoire, format 3.N', () {
      expect(CheckConfig.parse('pythonTarget: "3.10"').pythonTarget, '3.10');
      expect(const CheckConfig().pythonTarget, '3.9');
      expect(
          () => CheckConfig.parse('pythonTarget: 3.10'), throwsFormatException);
      expect(() => CheckConfig.parse('pythonTarget: "2.7"'),
          throwsFormatException);
      expect(pythonTag('3.11'), 'py311');
      expect(pythonTargetAtLeast('3.9', 10), isFalse);
      expect(pythonTargetAtLeast('3.12', 10), isTrue);
    });

    test('pylint et pyright désactivés par défaut, activables', () {
      const c = CheckConfig();
      expect(c.tool('pylint').enabled, isFalse);
      expect(c.tool('pyright').enabled, isFalse);
      expect(c.tool('ruff').enabled, isTrue);
      expect(c.withToolsEnabled(['pylint']).tool('pylint').enabled, isTrue);
    });

    test('dossier : .py et shebang python, dépendances exclues', () async {
      final d = await Directory.systemTemp.createTemp('cs_py_');
      addTearDown(() => d.delete(recursive: true));
      File('${d.path}/a.py').writeAsStringSync('x = 1\n');
      File('${d.path}/tool').writeAsStringSync('#!/usr/bin/env python3\n');
      File('${d.path}/notes.txt').writeAsStringSync('x\n');
      Directory('${d.path}/venv/lib').createSync(recursive: true);
      File('${d.path}/venv/lib/dep.py').writeAsStringSync('x = 1\n');
      final found = await collectScripts(d.path);
      expect(found!.map((f) => f.split('/').last), ['a.py', 'tool']);
    });
  });
}
