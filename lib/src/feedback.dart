/// Signalement des faux positifs : un cas par ligne JSON, avec un extrait
/// anonymisé, pour enrichir le corpus de test et corriger les règles.
///
/// Emplacement : `${XDG_DATA_HOME:-~/.local/share}/check-script/false-positives.jsonl`.
library;

import 'dart:convert';
import 'dart:io';

import 'model/finding.dart';
import 'model/report.dart';
import 'version.dart';

/// Lignes de contexte avant et après la ligne signalée.
const falsePositiveContext = 2;

final _string = RegExp(r'''("|')(?:\\.|(?!\1).)*\1''');
final _token = RegExp(r'[A-Za-z0-9+/_\-]{16,}={0,2}');

/// Ligne de code anonymisée : contenu des chaînes et jetons longs (clés,
/// empreintes, identifiants) remplacés par `…` ; la structure reste lisible
/// pour reproduire le cas.
String anonymizeCode(String line) => line
    .replaceAllMapped(_string, (m) => '${m[1]}…${m[1]}')
    .replaceAll(_token, '…');

class FalsePositive {
  final DateTime date;
  final String tool;
  final String rule;
  final String message;
  final String dialect;
  final Category category;
  final Severity severity;

  /// Extrait anonymisé, ligne signalée au centre (null : ligne masquée).
  final List<String?> context;

  /// Indice de la ligne signalée dans [context].
  final int focus;
  final String comment;

  const FalsePositive({
    required this.date,
    required this.tool,
    required this.rule,
    required this.message,
    required this.dialect,
    required this.category,
    required this.severity,
    required this.context,
    required this.focus,
    this.comment = '',
  });

  /// Cas tiré d'un problème de [report]. Les lignes où un secret a été
  /// détecté ne sont jamais recopiées, même anonymisées.
  factory FalsePositive.of(Finding f, ScriptReport report,
      {String comment = ''}) {
    final lines = report.script.displayLines;
    final masked = {
      for (final x in report.findings)
        if (x.line > 0 && x.snippet == null) x.line
    };
    final from = (f.line - falsePositiveContext).clamp(1, lines.length + 1);
    final to = (f.line + falsePositiveContext).clamp(0, lines.length);
    return FalsePositive(
      date: DateTime.now(),
      tool: f.tool,
      rule: f.ruleId,
      message: f.message,
      dialect: report.script.dialect.name,
      category: f.category,
      severity: f.severity,
      context: f.line < 1
          ? const []
          : [
              for (var n = from; n <= to; n++)
                masked.contains(n) ? null : anonymizeCode(lines[n - 1])
            ],
      focus: f.line < 1 ? -1 : f.line - from,
      comment: comment.trim(),
    );
  }

  Map<String, Object?> toJson() => {
        'date': date.toIso8601String(),
        'version': appVersion,
        'tool': tool,
        'rule': rule,
        'message': message,
        'dialect': dialect,
        'category': category.name,
        'severity': severity.name,
        'context': context,
        'focus': focus,
        if (comment.isNotEmpty) 'comment': comment,
      };
}

class FalsePositiveLog {
  FalsePositiveLog(this.file);

  final File file;

  static FalsePositiveLog? standard() {
    final env = Platform.environment;
    final base = env['XDG_DATA_HOME'] ??
        (env['HOME'] == null ? null : '${env['HOME']}/.local/share');
    return base == null
        ? null
        : FalsePositiveLog(File('$base/check-script/false-positives.jsonl'));
  }

  /// Ajoute un cas ; renvoie le nombre de cas enregistrés.
  Future<int> append(FalsePositive fp) async {
    await file.parent.create(recursive: true);
    await file.writeAsString('${jsonEncode(fp.toJson())}\n',
        mode: FileMode.append, flush: true);
    return (await read()).length;
  }

  /// Cas enregistrés (objets JSON), lignes illisibles ignorées.
  Future<List<Map<String, Object?>>> read() async {
    if (!await file.exists()) return [];
    return [
      for (final l in await file.readAsLines())
        if (l.trim().isNotEmpty)
          if (_decode(l) case final m?) m
    ];
  }

  static Map<String, Object?>? _decode(String l) {
    try {
      final j = jsonDecode(l);
      return j is Map<String, Object?> ? j : null;
    } on FormatException {
      return null;
    }
  }
}
