import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

void main() {
  test('registre : clés uniques, catalogue complet, titres bilingues', () {
    final fr = knownRules(Lang.fr);
    final keys = [for (final e in fr) e.key];
    expect(keys.toSet().length, keys.length);
    for (final r in ruleCatalog) {
      expect(keys, contains(r.id));
    }
    expect(fr.every((e) => e.title.isNotEmpty), isTrue);
    final en = {for (final e in knownRules(Lang.en)) e.key: e};
    expect(en['SC2086']!.title, contains('Unquoted'));
    expect(
        fr.firstWhere((e) => e.id == 'SC2086').title, contains('non quotée'));
  });

  test('registre : langage, classement et lien des codes externes', () {
    final r = {for (final e in knownRules(Lang.fr)) e.key: e};
    expect(r['SC2115']!.language, ToolLanguage.shell);
    expect(r['SC2115']!.severity, Severity.critical);
    expect(r['SC2115']!.url, contains('shellcheck.net/wiki/SC2115'));
    expect(r['S602']!.language, ToolLanguage.python);
    expect(r['S602']!.category, Category.security);
    expect(r['B602']!.severity, isNull); // fixée par Bandit
    expect(r['PYROB001']!.language, ToolLanguage.python);
    expect(r['SEC001']!.language, ToolLanguage.shell);
    expect(r['INVALID-SYNTAX']!.id, 'invalid-syntax');
    expect(r['FORMAT']!.tool, 'shfmt, ruff');
  });

  test('RuleEntry : JSON et problème rencontré', () {
    const f = Finding(
        tool: 'mypy',
        ruleId: 'arg-type',
        category: Category.robustness,
        severity: Severity.medium,
        line: 3,
        message: 'Argument 1 has incompatible type');
    final e = RuleEntry.fromFinding(f, python: true);
    expect(e.key, 'ARG-TYPE');
    expect(e.language, ToolLanguage.python);
    final back = RuleEntry.fromJson(e.toJson())!;
    expect((
      back.id,
      back.tool,
      back.title,
      back.severity
    ), (
      'arg-type',
      'mypy',
      'Argument 1 has incompatible type',
      Severity.medium
    ));
    expect(RuleEntry.fromJson({'id': 1}), isNull);
  });
}
