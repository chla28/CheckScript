/// Tests avec les vrais outils externes : chaque test est ignoré si l'outil
/// n'est pas installé (ils valident le contrat de sortie des outils).
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

bool _has(String tool) {
  try {
    return Process.runSync('sh', ['-c', 'command -v $tool']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

String? _skip(String tool) => _has(tool) ? null : '$tool non installé';

void main() {
  final engine = Engine(lang: Lang.en);

  test('bash -n détecte l\'erreur de syntaxe', () async {
    final r = await engine.analyzeFile(fixture('syntax_error.sh'));
    expect(
        r.findings
            .where((f) => f.ruleId == 'SYNTAX' || f.ruleId.startsWith('SC1')),
        isNotEmpty);
    expect(r.score(Category.robustness).score, lessThanOrEqualTo(8));
  }, skip: _skip('bash'));

  test('shellcheck réel sur bad.sh', () async {
    final r = await engine.analyzeFile(fixture('bad.sh'));
    expect(r.tools.firstWhere((t) => t.tool == 'shellcheck').status,
        ToolStatus.ok);
    expect(ids(r.findings), containsAll(['SC2164', 'SC2086']));
  }, skip: _skip('shellcheck'));

  test('checkbashisms réel sur posix.sh', () async {
    final r = await Engine(
            config:
                const CheckConfig().withToolsDisabled(['shellcheck', 'shfmt']))
        .analyzeFile(fixture('posix.sh'));
    expect(r.findings.where((f) => f.tool == 'checkbashisms'), isNotEmpty);
  }, skip: _skip('checkbashisms'));

  test('shfmt réel : good.sh bien formaté', () async {
    final r = await engine.analyzeFile(fixture('good.sh'));
    expect(r.findings.where((f) => f.tool == 'shfmt'), isEmpty);
  }, skip: _skip('shfmt'));

  test('bashate réel : good.sh (indentation 2) sans E003', () async {
    final r = await engine.analyzeFile(fixture('good.sh'));
    expect(ids(r.findings), isNot(contains('E003')));
  }, skip: _skip('bashate'));

  test('good.sh obtient A avec tous les outils disponibles', () async {
    final r = await engine.analyzeFile(fixture('good.sh'));
    expect(r.grade, 'A', reason: r.findings.join('\n'));
  });

  // ── Python ──────────────────────────────────────────────────────────────
  // Sans semgrep : son registre demande un accès réseau.
  final pyEngine = Engine(
      lang: Lang.en,
      config: const CheckConfig().withToolsDisabled(['semgrep']));

  test('compilation Python : erreur de syntaxe située', () async {
    final r = await pyEngine
        .analyze(ScriptInfo.fromContent('s.py', 'def f(:\n    pass\n'));
    final s = r.findings.firstWhere((f) => f.ruleId == 'SYNTAX');
    expect(s.line, 1);
    expect(s.severity, Severity.critical);
  }, skip: _skip('python3'));

  for (final (tool, rules) in [
    ('ruff', ['E722', 'E401']),
    ('bandit', ['B602', 'B105']),
    ('mypy', ['operator']),
    ('radon', ['CC']),
  ]) {
    test('$tool réel sur bad.py', () async {
      final r = await pyEngine.analyzeFile(fixture('bad.py'));
      expect(r.tools.firstWhere((t) => t.tool == tool).status, ToolStatus.ok);
      expect(ids(r.findings), containsAll(rules));
    }, skip: _skip(tool));
  }

  test('vermin réel : match au-delà de Python 3.9', () async {
    final r = await Engine(
            lang: Lang.en,
            config: const CheckConfig().withToolsDisabled(['ruff', 'semgrep']))
        .analyzeFile(fixture('bad.py'));
    expect(r.findings.where((f) => f.tool == 'vermin' && f.line == 50),
        isNotEmpty);
  }, skip: _skip('vermin'));

  test('good.py obtient A (avec ou sans outils)', () async {
    final good = await pyEngine.analyzeFile(fixture('good.py'));
    expect(good.grade, 'A', reason: good.findings.join('\n'));
  });

  // Les défauts graves de bad.py (shell=True, eval, pickle, secret…) sont
  // détectés par Bandit et Ruff : sans eux, seules les règles intégrées
  // s'appliquent (note élevée, cas des serveurs de CI).
  test('bad.py moins de 6 avec Bandit et Ruff', () async {
    final bad = await pyEngine.analyzeFile(fixture('bad.py'));
    expect(bad.global, lessThan(6), reason: bad.findings.join('\n'));
  }, skip: _skip('bandit') ?? _skip('ruff'));
}
