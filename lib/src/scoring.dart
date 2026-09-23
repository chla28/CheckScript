/// Calcul des notes /10 par catégorie et de la note globale.
library;

import 'dart:math' as math;

import 'config.dart';
import 'model/finding.dart';

class CategoryScore {
  final Category category;

  /// Note sur 10, arrondie au dixième.
  final double score;
  final Map<Severity, int> counts;

  const CategoryScore(this.category, this.score, this.counts);

  int get total => counts.values.fold(0, (a, b) => a + b);
  int count(Severity s) => counts[s] ?? 0;

  Map<String, Object?> toJson() => {
        'category': category.name,
        'score': score,
        'total': total,
        for (final s in Severity.values) s.name: count(s),
      };
}

/// Facteur d'atténuation des pénalités Medium/Low selon la taille du script :
/// 1 jusqu'à [ScoringConfig.referenceLines] lignes de code, puis
/// √(référence / lignes). Une même densité de défauts coûte ainsi à peu près
/// autant à un long script qu'à un court.
double sizeFactor(int codeLines, ScoringConfig cfg) {
  final ref = math.max(1, cfg.referenceLines);
  return math.sqrt(ref / math.max(ref, codeLines));
}

/// Note d'une catégorie.
///
/// Les problèmes sont regroupés par règle (outil + identifiant + sévérité) :
/// une règle déclenchée n fois coûte `poids × (1 + log2 n)`, car des
/// occurrences répétées traduisent en général une seule habitude à corriger.
/// Les pénalités Medium/Low sont multipliées par [sizeFactor] ; Critical/High
/// ne sont jamais atténuées.
CategoryScore scoreCategory(
    Category cat, List<Finding> findings, int codeLines, ScoringConfig cfg) {
  final mine = findings.where((f) => f.category == cat).toList();
  final counts = {for (final s in Severity.values) s: 0};
  final groups = <String, (Severity, int)>{};
  for (final f in mine) {
    counts[f.severity] = counts[f.severity]! + 1;
    final key = '${f.tool}|${f.ruleId}|${f.severity.name}';
    final g = groups[key];
    groups[key] = (f.severity, (g?.$2 ?? 0) + 1);
  }
  final factor = sizeFactor(codeLines, cfg);
  var penalty = 0.0;
  for (final (sev, n) in groups.values) {
    final w = cfg.weights[sev] ?? 0;
    final damped = w * (1 + math.log(n) / math.ln2);
    penalty += sev == Severity.critical || sev == Severity.high
        ? damped
        : damped * factor;
  }
  final score = (10 - penalty).clamp(0.0, 10.0);
  return CategoryScore(cat, (score * 10).round() / 10, counts);
}

/// Écart maximal entre la note globale et la plus faible note de catégorie.
const maxGapToWorst = 1.5;

/// Note globale : moyenne des catégories pondérée par
/// [ScoringConfig.categoryWeights], plafonnée à la plus faible note de
/// catégorie + [maxGapToWorst] (une catégorie très faible ne peut pas être
/// masquée par les autres), arrondie au dixième.
double globalScore(List<CategoryScore> scores, ScoringConfig cfg) {
  var sum = 0.0, weights = 0.0;
  var worst = 10.0;
  for (final s in scores) {
    final w = cfg.categoryWeights[s.category] ?? 1;
    sum += s.score * w;
    weights += w;
    if (s.score < worst) worst = s.score;
  }
  if (weights == 0) return 0;
  final mean = math.min(sum / weights, worst + maxGapToWorst);
  return (mean * 10).round() / 10;
}

/// Niveau lisible : A (≥ 9), B (≥ 7,5), C (≥ 6), D (≥ 4), E.
String gradeFor(double score) {
  if (score >= 9) return 'A';
  if (score >= 7.5) return 'B';
  if (score >= 6) return 'C';
  if (score >= 4) return 'D';
  return 'E';
}
