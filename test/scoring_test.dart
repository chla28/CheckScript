import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

Finding f(Severity s,
        {String rule = 'R',
        Category c = Category.security,
        String tool = 't'}) =>
    Finding(
        tool: tool,
        ruleId: rule,
        category: c,
        severity: s,
        line: 1,
        message: 'm');

void main() {
  const cfg = ScoringConfig();

  test('aucun problème : 10', () {
    final s = scoreCategory(Category.security, [], 50, cfg);
    expect(s.score, 10);
    expect(s.total, 0);
  });

  test('poids par sévérité', () {
    double score(Severity sev) =>
        scoreCategory(Category.security, [f(sev)], 50, cfg).score;
    expect(score(Severity.critical), 6);
    expect(score(Severity.high), 8);
    expect(score(Severity.medium), 9.3); // 9,25 arrondi
    expect(score(Severity.low), 9.8);
  });

  test('occurrences répétées d\'une même règle atténuées (1 + log2 n)', () {
    final s = scoreCategory(
        Category.security, List.filled(4, f(Severity.high)), 50, cfg);
    expect(s.score, 4); // 2 × (1 + 2)
    expect(s.count(Severity.high), 4);
  });

  test('règles distinctes : pénalités additionnées', () {
    final s = scoreCategory(Category.security,
        [f(Severity.high, rule: 'A'), f(Severity.high, rule: 'B')], 50, cfg);
    expect(s.score, 6);
  });

  test('plancher à 0', () {
    final s = scoreCategory(
        Category.security,
        [for (var i = 0; i < 5; i++) f(Severity.critical, rule: '$i')],
        50,
        cfg);
    expect(s.score, 0);
  });

  test('taille : Medium/Low atténués, Critical/High non', () {
    expect(sizeFactor(50, cfg), 1);
    expect(sizeFactor(400, cfg), closeTo(0.5, 1e-9));
    final lows = [for (var i = 0; i < 8; i++) f(Severity.low, rule: '$i')];
    expect(scoreCategory(Category.security, lows, 100, cfg).score, 8);
    expect(scoreCategory(Category.security, lows, 400, cfg).score, 9);
    final high = [f(Severity.high)];
    expect(scoreCategory(Category.security, high, 400, cfg).score, 8);
  });

  test('seules les entrées de la catégorie comptent', () {
    final s = scoreCategory(
        Category.performance,
        [f(Severity.critical), f(Severity.low, c: Category.performance)],
        50,
        cfg);
    expect(s.total, 1);
  });

  test('note globale pondérée, plafonnée à la pire catégorie + 1,5', () {
    CategoryScore cs(Category c, double v) => CategoryScore(c, v, const {});
    final all10 = [for (final c in Category.values) cs(c, 10)];
    expect(globalScore(all10, cfg), 10);
    final oneBad = [
      for (final c in Category.values) cs(c, c == Category.performance ? 2 : 10)
    ];
    expect(globalScore(oneBad, cfg), 3.5);
    final mixed = [
      cs(Category.security, 8),
      cs(Category.robustness, 6),
      cs(Category.maintainability, 7),
      cs(Category.portability, 9),
      cs(Category.performance, 10),
    ];
    // (8×1,5 + 6×1,25 + 7 + 9×0,75 + 10×0,5) / 5 = 7,65, plafonné à 6 + 1,5
    expect(globalScore(mixed, cfg), 7.5);
    final close = [
      for (final c in Category.values) cs(c, c == Category.performance ? 8 : 9)
    ];
    // Moyenne 8,9 sous le plafond 9,5 : non plafonnée.
    expect(globalScore(close, cfg), 8.9);
  });

  test('niveaux', () {
    expect(gradeFor(9.5), 'A');
    expect(gradeFor(7.5), 'B');
    expect(gradeFor(6), 'C');
    expect(gradeFor(4), 'D');
    expect(gradeFor(3.9), 'E');
  });
}
