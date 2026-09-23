import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

void main() {
  test('document vide : valeurs par défaut', () {
    final c = CheckConfig.parse('');
    expect(c.tool('shellcheck').enabled, isTrue);
    expect(c.tool('shellcheck').exclude, ['SC1091']);
    expect(c.scoring.weights[Severity.critical], 4);
    expect(c.thresholds.maxLineLength, 120);
  });

  test('configuration complète', () {
    final c = CheckConfig.parse('''
tools:
  shellcheck:
    path: /opt/sc/shellcheck
    exclude: [SC2034, SC1090]
  bashate: false
rules:
  disabled: [mnt005, E006]
  overrides:
    SC2086: { category: security, severity: high }
scoring:
  weights: { low: 0.5 }
  referenceLines: 200
  categoryWeights: { performance: 0 }
thresholds:
  maxLineLength: 100
  maxFunctionLines: 40
''');
    expect(c.tool('shellcheck').executable, '/opt/sc/shellcheck');
    expect(c.tool('shellcheck').exclude, ['SC2034', 'SC1090']);
    expect(c.tool('bashate').enabled, isFalse);
    expect(c.disabledRules, {'MNT005', 'E006'});
    expect(c.overrides['SC2086']!.category, Category.security);
    expect(c.overrides['SC2086']!.severity, Severity.high);
    expect(c.scoring.weights[Severity.low], 0.5);
    expect(c.scoring.weights[Severity.high], 2);
    expect(c.scoring.referenceLines, 200);
    expect(c.scoring.categoryWeights[Category.performance], 0);
    expect(c.thresholds.maxLineLength, 100);
    expect(c.thresholds.maxFunctionLines, 40);
    expect(c.thresholds.maxNesting, 4);
  });

  test('erreurs', () {
    expect(() => CheckConfig.parse('- a\n- b'), throwsFormatException);
    expect(
        () =>
            CheckConfig.parse('rules:\n  overrides:\n    X: {severity: huge}'),
        throwsFormatException);
    expect(() => CheckConfig.parse('scoring:\n  weights: {low: abc}'),
        throwsFormatException);
  });

  test('withToolsDisabled', () {
    final c = const CheckConfig().withToolsDisabled(['shfmt']);
    expect(c.tool('shfmt').enabled, isFalse);
    expect(c.tool('shellcheck').enabled, isTrue);
  });
}
