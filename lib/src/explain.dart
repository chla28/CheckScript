/// Explication de la note : ce que coûte chaque règle déclenchée, et les
/// corrections qui font gagner un niveau (« corriger ces 3 points → B »).
library;

import 'dart:math' as math;

import 'config.dart';
import 'model/finding.dart';
import 'scoring.dart';

/// Effet d'une règle (outil + identifiant) sur la note d'un script.
class RuleImpact {
  final String tool;
  final String ruleId;
  final Category category;

  /// Sévérité la plus forte parmi ses occurrences.
  final Severity severity;
  final int occurrences;

  /// Points retirés à sa catégorie (avant plafonnement à 0).
  final double penalty;

  /// Gain de la note globale si toutes ses occurrences sont corrigées.
  final double gain;

  /// Au moins une occurrence a une correction automatique.
  final bool fixable;
  final String message;

  const RuleImpact({
    required this.tool,
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.occurrences,
    required this.penalty,
    required this.gain,
    required this.fixable,
    required this.message,
  });

  String get key => '$tool|$ruleId';

  Map<String, Object?> toJson() => {
        'tool': tool,
        'rule': ruleId,
        'category': category.name,
        'severity': severity.name,
        'occurrences': occurrences,
        'penalty': _r(penalty),
        'gain': _r(gain),
        'fixable': fixable,
        'message': message,
      };

  static RuleImpact? fromJson(Object? j) {
    if (j is! Map) return null;
    return RuleImpact(
      tool: '${j['tool']}',
      ruleId: '${j['rule']}',
      category: Category.tryParse('${j['category']}') ?? Category.robustness,
      severity: Severity.tryParse('${j['severity']}') ?? Severity.low,
      occurrences: (j['occurrences'] as num?)?.toInt() ?? 0,
      penalty: (j['penalty'] as num?)?.toDouble() ?? 0,
      gain: (j['gain'] as num?)?.toDouble() ?? 0,
      fixable: j['fixable'] == true,
      message: '${j['message'] ?? ''}',
    );
  }
}

double _r(double v) => (v * 100).round() / 100;

class ScoreExplanation {
  /// Règles déclenchées, de la plus coûteuse (gain global) à la moins.
  final List<RuleImpact> impacts;

  /// Règles à corriger pour atteindre [nextGrade] (vide au niveau A, ou si
  /// aucune combinaison raisonnable n'y suffit).
  final List<RuleImpact> plan;
  final String? nextGrade;

  /// Note globale obtenue après le [plan].
  final double? planScore;

  const ScoreExplanation(
      this.impacts, this.plan, this.nextGrade, this.planScore);

  static const empty = ScoreExplanation([], [], null, null);

  /// Gain global d'une règle (0 si inconnue).
  double gainOf(String tool, String ruleId) =>
      impacts
          .firstWhereOrNull((i) => i.tool == tool && i.ruleId == ruleId)
          ?.gain ??
      0;

  Map<String, Object?> toJson() => {
        'impacts': [for (final i in impacts) i.toJson()],
        if (nextGrade != null)
          'nextGrade': {
            'grade': nextGrade,
            'score': planScore,
            'fix': [for (final i in plan) '${i.tool}/${i.ruleId}'],
          },
      };

  static ScoreExplanation fromJson(Object? j) {
    if (j is! Map) return empty;
    final impacts = [
      for (final i in (j['impacts'] as List? ?? const []))
        if (RuleImpact.fromJson(i) case final r?) r
    ];
    final ng = j['nextGrade'];
    if (ng is! Map) return ScoreExplanation(impacts, const [], null, null);
    final keys = {for (final k in (ng['fix'] as List? ?? const [])) '$k'};
    return ScoreExplanation(
      impacts,
      [
        for (final i in impacts)
          if (keys.contains('${i.tool}/${i.ruleId}')) i
      ],
      '${ng['grade']}',
      (ng['score'] as num?)?.toDouble(),
    );
  }
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

/// Nombre maximal de règles proposées pour gagner un niveau.
const maxPlanSteps = 10;

double _global(List<Finding> fs, int codeLines, ScoringConfig cfg) =>
    globalScore(
        [for (final c in Category.values) scoreCategory(c, fs, codeLines, cfg)],
        cfg);

/// Explique la note de [findings] : gain de chaque règle corrigée seule,
/// puis règles choisies une à une (la plus rentable d'abord) jusqu'au niveau
/// supérieur.
ScoreExplanation explainScore(
    List<Finding> findings, int codeLines, ScoringConfig cfg) {
  if (findings.isEmpty) return ScoreExplanation.empty;
  final groups = <String, List<Finding>>{};
  for (final f in findings) {
    (groups['${f.tool}|${f.ruleId}'] ??= []).add(f);
  }
  final base = _global(findings, codeLines, cfg);
  final factor = sizeFactor(codeLines, cfg);

  List<Finding> without(Set<String> keys) => [
        for (final f in findings)
          if (!keys.contains('${f.tool}|${f.ruleId}')) f
      ];

  final impacts = <RuleImpact>[];
  for (final e in groups.entries) {
    final fs = e.value;
    // Pénalité de la règle dans sa catégorie (même calcul que scoreCategory).
    var penalty = 0.0;
    final bySev = <Severity, int>{};
    for (final f in fs) {
      bySev[f.severity] = (bySev[f.severity] ?? 0) + 1;
    }
    bySev.forEach((sev, n) {
      final w = cfg.weights[sev] ?? 0;
      final damped = w * (1 + _log2(n));
      penalty += sev == Severity.critical || sev == Severity.high
          ? damped
          : damped * factor;
    });
    final f = fs.first;
    impacts.add(RuleImpact(
      tool: f.tool,
      ruleId: f.ruleId,
      category: f.category,
      severity:
          fs.map((x) => x.severity).reduce((a, b) => b.index < a.index ? b : a),
      occurrences: fs.length,
      penalty: penalty,
      gain: _global(without({e.key}), codeLines, cfg) - base,
      fixable: fs.any((x) => x.edits.isNotEmpty),
      message: f.message,
    ));
  }
  impacts.sort((a, b) {
    final c = b.gain.compareTo(a.gain);
    if (c != 0) return c;
    final p = b.penalty.compareTo(a.penalty);
    return p != 0 ? p : a.key.compareTo(b.key);
  });

  // Plan glouton vers le niveau supérieur.
  final grade = gradeFor(base);
  const order = ['A', 'B', 'C', 'D', 'E'];
  if (grade == 'A') return ScoreExplanation(impacts, const [], null, null);
  final target = order[order.indexOf(grade) - 1];
  final chosen = <String>{};
  final plan = <RuleImpact>[];
  var score = base;
  while (gradeFor(score) != target &&
      order.indexOf(gradeFor(score)) > order.indexOf(target) &&
      plan.length < maxPlanSteps) {
    RuleImpact? best;
    var bestScore = score;
    for (final i in impacts) {
      if (chosen.contains(i.key)) continue;
      final s = _global(without({...chosen, i.key}), codeLines, cfg);
      if (s > bestScore) {
        best = i;
        bestScore = s;
      }
    }
    // Aucune correction isolée ne fait progresser la note (catégorie déjà à
    // 0) : la règle la plus pénalisante est retenue, les suivantes feront
    // remonter la catégorie.
    if (best == null) {
      for (final i in impacts) {
        if (!chosen.contains(i.key) &&
            (best == null || i.penalty > best.penalty)) {
          best = i;
        }
      }
      if (best == null) break;
      bestScore = _global(without({...chosen, best.key}), codeLines, cfg);
    }
    chosen.add(best.key);
    plan.add(best);
    score = bestScore;
  }
  final reached = order.indexOf(gradeFor(score)) <= order.indexOf(target);
  return reached
      ? ScoreExplanation(impacts, plan, gradeFor(score), score)
      : ScoreExplanation(impacts, const [], null, null);
}

double _log2(int n) => math.log(n) / math.ln2;

/// Bonus d'une règle corrigeable automatiquement dans le tri par gain
/// rapide : un clic suffit, elle passe devant à gain comparable.
const autoFixBonus = 1.5;

/// Intérêt d'une règle pour le tri par gain rapide.
double quickWin(RuleImpact i) => i.gain * (i.fixable ? autoFixBonus : 1);

/// Problèmes triés par gain rapide : règle la plus rentable d'abord (gain
/// sur la note globale, bonus si corrigeable automatiquement), puis
/// sévérité et ligne.
List<Finding> sortByQuickWin(List<Finding> findings, ScoreExplanation e) {
  final rank = {for (final i in e.impacts) i.key: quickWin(i)};
  double r(Finding f) => rank['${f.tool}|${f.ruleId}'] ?? 0;
  return [...findings]..sort((a, b) {
      var c = r(b).compareTo(r(a));
      if (c != 0) return c;
      c = a.severity.index.compareTo(b.severity.index);
      return c != 0 ? c : a.line.compareTo(b.line);
    });
}
