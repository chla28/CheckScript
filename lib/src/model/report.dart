/// Résultat complet de l'analyse d'un script.
library;

import '../analyzers/commands.dart';
import '../explain.dart';
import '../scoring.dart';
import '../script_info.dart';
import 'finding.dart';

/// Comparaison avec une analyse de référence (baseline).
class Comparison {
  /// Problèmes absents de la référence.
  final List<Finding> added;

  /// Nombre de problèmes de la référence qui ont disparu.
  final int fixed;

  /// Nombre de problèmes présents dans les deux analyses.
  final int unchanged;
  final double previousGlobal;
  final Map<Category, double> previousScores;

  const Comparison({
    required this.added,
    required this.fixed,
    required this.unchanged,
    required this.previousGlobal,
    required this.previousScores,
  });

  Map<String, Object?> toJson() => {
        'new': added.length,
        'fixed': fixed,
        'unchanged': unchanged,
        'previousGlobal': previousGlobal,
        'previousScores': {
          for (final e in previousScores.entries) e.key.name: e.value
        },
      };
}

class ScriptReport {
  final ScriptInfo script;
  final List<ToolRun> tools;

  /// Problèmes dédoublonnés, triés par catégorie, sévérité puis ligne.
  final List<Finding> findings;
  final List<CategoryScore> scores;
  final double global;
  final DateTime date;

  /// Problèmes neutralisés par des directives `# check-script disable=…`.
  final int suppressed;

  /// Profil et contextes utilisés (traçabilité du rapport).
  final String profile;
  final List<String> contexts;

  /// Comparaison avec la référence, si `--baseline` a été fourni.
  final Comparison? comparison;

  /// Ce que coûte chaque règle, et comment gagner un niveau.
  final ScoreExplanation explanation;

  /// Commandes externes du script (shell), avec leur présence et leur paquet.
  final List<CommandUse> commands;

  const ScriptReport({
    required this.script,
    required this.tools,
    required this.findings,
    required this.scores,
    required this.global,
    required this.date,
    this.suppressed = 0,
    this.profile = 'standard',
    this.contexts = const [],
    this.comparison,
    this.explanation = ScoreExplanation.empty,
    this.commands = const [],
  });

  /// Même rapport, problèmes limités à [kept] (filtre d'affichage : les
  /// notes restent celles de l'analyse complète).
  ScriptReport withFindings(List<Finding> kept) => ScriptReport(
        script: script,
        tools: tools,
        findings: kept,
        scores: scores,
        global: global,
        date: date,
        suppressed: suppressed,
        profile: profile,
        contexts: contexts,
        comparison: comparison,
        explanation: explanation,
        commands: commands,
      );

  ScriptReport withComparison(Comparison? c) => ScriptReport(
        script: script,
        tools: tools,
        findings: findings,
        scores: scores,
        global: global,
        date: date,
        suppressed: suppressed,
        profile: profile,
        contexts: contexts,
        comparison: c,
        explanation: explanation,
        commands: commands,
      );

  /// Relit [toJson] pour [script] (cache des résultats) ; la comparaison
  /// avec une référence n'est pas conservée. Lève en cas de format invalide.
  factory ScriptReport.fromJson(Map<String, Object?> j, ScriptInfo script) {
    final g = j['global'] as Map;
    return ScriptReport(
      script: script,
      tools: [
        for (final t in j['tools'] as List)
          ToolRun.fromJson((t as Map).cast<String, Object?>())
      ],
      findings: [
        for (final f in j['findings'] as List)
          Finding.fromJson((f as Map).cast<String, Object?>())
      ],
      scores: [
        for (final s in j['categories'] as List)
          CategoryScore.fromJson((s as Map).cast<String, Object?>())
      ],
      global: (g['score'] as num).toDouble(),
      date: DateTime.parse('${j['date']}'),
      suppressed: (j['suppressed'] as num?)?.toInt() ?? 0,
      profile: '${j['profile'] ?? 'standard'}',
      contexts: [for (final c in (j['contexts'] as List? ?? const [])) '$c'],
      explanation: ScoreExplanation.fromJson(j['explanation']),
      commands: [
        for (final c in j['commands'] as List? ?? const [])
          CommandUse.fromJson((c as Map).cast<String, Object?>())
      ],
    );
  }

  String get grade => gradeFor(global);

  CategoryScore score(Category c) => scores.firstWhere((s) => s.category == c);

  List<Finding> findingsOf(Category c) =>
      findings.where((f) => f.category == c).toList();

  Map<String, Object?> toJson() => {
        'file': script.path,
        'dialect': script.dialect.name,
        if (script.embedded case final e?)
          'embedded': {'kind': e.kind.name, 'blocks': e.blocks.length},
        'lines': {
          'total': script.totalLines,
          'code': script.codeLines,
          'comments': script.commentLines,
        },
        'date': date.toIso8601String(),
        'profile': profile,
        if (contexts.isNotEmpty) 'contexts': contexts,
        'global': {'score': global, 'grade': grade},
        'categories': [for (final s in scores) s.toJson()],
        'suppressed': suppressed,
        if (explanation.impacts.isNotEmpty) 'explanation': explanation.toJson(),
        if (comparison != null) 'comparison': comparison!.toJson(),
        'tools': [for (final t in tools) t.toJson()],
        if (commands.isNotEmpty)
          'commands': [for (final c in commands) c.toJson()],
        'findings': [for (final f in findings) f.toJson()],
      };
}
