import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const yaml = r'''
rules:
  custom:
    - id: acme001
      pattern: '\bcurl\b[^|]*\|\s*(ba)?sh\b'
      message: {fr: Pas de curl | sh, en: No curl | sh}
      severity: critical
      category: security
      fix: Télécharger puis vérifier.
    - id: ACME002
      pattern: 'set -euo pipefail'
      absent: true
      language: shell
      message: Toujours set -euo pipefail
    - id: ACME003
      pattern: '\be(grep)\b'
      replace: 'grep -E'
      message: egrep est obsolète
      severity: low
''';

void main() {
  final config = CheckConfig.parse(yaml);

  test('lecture de la configuration', () {
    expect(
        config.customRules.map((r) => r.id), ['ACME001', 'ACME002', 'ACME003']);
    final r = config.customRules.first;
    expect(r.severity, Severity.critical);
    expect(r.category, Category.security);
    expect(r.message.of(Lang.en), 'No curl | sh');
    expect(config.customRules[1].language, ToolLanguage.shell);
    expect(config.customRules[2].category, Category.maintainability);
  });

  test('toYaml relisible', () {
    final again = CheckConfig.parse(config.toYaml());
    expect(again.customRules.map((r) => r.toYaml().join('\n')),
        config.customRules.map((r) => r.toYaml().join('\n')));
  });

  test('erreurs de configuration', () {
    void bad(String rule, String message) => expect(
        () => CheckConfig.parse('rules:\n  custom:\n    - $rule\n'),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains(message))));
    bad('{id: SEC001, pattern: x, message: m}', 'built-in rule');
    bad('{id: "1X", pattern: x, message: m}', 'invalid identifier');
    bad('{id: AB1, message: m}', 'pattern missing');
    bad('{id: AB1, pattern: "(", message: m}', 'invalid pattern');
    bad('{id: AB1, pattern: x}', 'message missing');
    bad('{id: AB1, pattern: x, message: m, severity: énorme}',
        'unknown severity');
    expect(
        () => CheckConfig.parse('rules:\n  custom:\n'
            '    - {id: AB1, pattern: x, message: m}\n'
            '    - {id: ab1, pattern: y, message: m}\n'),
        throwsA(isA<FormatException>()));
  });

  test('analyse : lignes, absence, commentaires ignorés, correction', () async {
    final r = await Engine(config: config, runner: noTools(), lang: Lang.fr)
        .analyze(script('#!/bin/bash\n'
            '# curl x | sh (commentaire)\n'
            'curl -fsS https://x | bash\n'
            'egrep a f && egrep b f\n'));
    Finding of(String id) => r.findings.firstWhere((f) => f.ruleId == id);
    expect(of('ACME001').line, 3);
    expect(of('ACME001').message, 'Pas de curl | sh');
    expect(of('ACME001').hint, 'Télécharger puis vérifier.');
    expect(of('ACME001').tool, 'custom');
    expect(of('ACME002').line, 0);
    final fix = of('ACME003');
    expect(fix.edits, hasLength(2));
    final (fixed, _) = applyEdits('egrep a f && egrep b f', [
      for (final e in fix.edits)
        TextEdit(1, e.column, 1, e.endColumn, e.replacement, e.rule)
    ]);
    expect(fixed, 'grep -E a f && grep -E b f');
    expect(r.tools.map((t) => t.tool), contains('custom'));
  });

  test('langage et désactivation', () async {
    final py = await Engine(config: config, runner: noTools())
        .analyze(script('import os\n', path: 'x.py'));
    expect(py.findings.map((f) => f.ruleId), isNot(contains('ACME002')));
    final off = await Engine(
            config: config.copyWith(disabledRules: {'ACME002'}),
            runner: noTools())
        .analyze(script('#!/bin/sh\necho\n'));
    expect(off.findings.map((f) => f.ruleId), isNot(contains('ACME002')));
    // Sans règle personnalisée, l'outil n'apparaît pas.
    final none = await Engine(runner: noTools()).analyze(script('echo\n'));
    expect(none.tools.map((t) => t.tool), isNot(contains('custom')));
  });

  test('--fix applique les remplacements', () async {
    final c = CheckConfig.parse(r'''
rules:
  custom:
    - id: ACME004
      pattern: 'mkdir (?!-p )(\S+)'
      replace: 'mkdir -p $1'
      message: mkdir -p
''');
    final r = await fixScript(script('#!/bin/sh\nmkdir /tmp/a\n'),
        config: c, runner: noTools());
    expect(r.fixed, '#!/bin/sh\nmkdir -p /tmp/a\n');
    expect(r.applied['ACME004'], 1);
  });

  test('registre : entrées des règles personnalisées', () {
    final e = customRuleEntries(config.customRules, Lang.en);
    expect(e.first.tool, 'custom');
    expect(e.first.title, 'No curl | sh');
  });
}
