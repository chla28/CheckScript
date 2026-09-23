/// Résultat complet de l'analyse d'un script.
library;

import '../scoring.dart';
import '../script_info.dart';
import 'finding.dart';

class ScriptReport {
  final ScriptInfo script;
  final List<ToolRun> tools;

  /// Problèmes dédoublonnés, triés par catégorie, sévérité puis ligne.
  final List<Finding> findings;
  final List<CategoryScore> scores;
  final double global;
  final DateTime date;

  const ScriptReport({
    required this.script,
    required this.tools,
    required this.findings,
    required this.scores,
    required this.global,
    required this.date,
  });

  String get grade => gradeFor(global);

  CategoryScore score(Category c) => scores.firstWhere((s) => s.category == c);

  List<Finding> findingsOf(Category c) =>
      findings.where((f) => f.category == c).toList();

  Map<String, Object?> toJson() => {
        'file': script.path,
        'dialect': script.dialect.name,
        'lines': {
          'total': script.totalLines,
          'code': script.codeLines,
          'comments': script.commentLines,
        },
        'date': date.toIso8601String(),
        'global': {'score': global, 'grade': grade},
        'categories': [for (final s in scores) s.toJson()],
        'tools': [for (final t in tools) t.toJson()],
        'findings': [for (final f in findings) f.toJson()],
      };
}
