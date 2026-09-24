/// Modèle de base : catégories, sévérités et problèmes détectés.
library;

import '../json_num.dart';

/// Les cinq axes du classement, dans l'ordre d'affichage.
enum Category {
  security,
  robustness,
  maintainability,
  portability,
  performance;

  static Category? tryParse(String s) {
    for (final c in values) {
      if (c.name == s.toLowerCase()) return c;
    }
    return null;
  }
}

/// Gravité d'un problème, de la plus forte à la plus faible.
enum Severity {
  critical,
  high,
  medium,
  low;

  static Severity? tryParse(String s) {
    for (final v in values) {
      if (v.name == s.toLowerCase()) return v;
    }
    return null;
  }

  /// Libellé anglais normalisé (identique dans les deux langues de l'outil).
  String get label => switch (this) {
        Severity.critical => 'Critical',
        Severity.high => 'High',
        Severity.medium => 'Medium',
        Severity.low => 'Low',
      };
}

/// Remplacement de texte (positions 1-based, fin exclusive, tabulation = 1
/// colonne), tel que ShellCheck le propose dans sa sortie `json1`.
class TextEdit {
  final int line, column, endLine, endColumn;
  final String replacement;
  final String rule;
  const TextEdit(this.line, this.column, this.endLine, this.endColumn,
      this.replacement, this.rule);

  factory TextEdit.fromJson(Map<String, Object?> j, String rule) => TextEdit(
        jsonInt(j['line']) ?? 1,
        jsonInt(j['column']) ?? 1,
        jsonInt(j['endLine']) ?? 1,
        jsonInt(j['endColumn']) ?? 1,
        '${j['replacement']}',
        rule,
      );

  Map<String, Object?> toJson() => {
        'line': line,
        'column': column,
        'endLine': endLine,
        'endColumn': endColumn,
        'replacement': replacement,
      };
}

/// Un problème détecté dans un script, quel que soit l'outil d'origine.
class Finding {
  /// Outil ayant produit le problème (`shellcheck`, `builtin`, `bashate`…).
  final String tool;

  /// Identifiant de la règle dans l'outil (`SC2086`, `E003`, `SEC001`…).
  final String ruleId;

  final Category category;
  final Severity severity;

  /// Ligne (1-based) ; 0 si le problème concerne le fichier entier.
  final int line;
  final int column;
  final String message;

  /// Extrait de code concerné (facultatif).
  final String? snippet;

  /// Codes ShellCheck équivalents : si ShellCheck a signalé l'un d'eux sur la
  /// même ligne, ce problème (issu des règles intégrées) est dédoublonné.
  final List<String> equivalents;

  /// Conseil de correction (langue du rapport), facultatif.
  final String? hint;

  /// Documentation de la règle (ex. wiki ShellCheck), facultative.
  final String? url;

  /// Empreinte stable (indépendante du numéro de ligne) servant à comparer
  /// deux analyses (baseline) ; calculée par le moteur.
  final String? fingerprint;

  /// Correction concrète de ce problème (vide si aucune correction sûre).
  final List<TextEdit> edits;

  const Finding({
    required this.tool,
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.line,
    this.column = 0,
    required this.message,
    this.snippet,
    this.equivalents = const [],
    this.hint,
    this.url,
    this.fingerprint,
    this.edits = const [],
  });

  Finding copyWith(
          {Category? category,
          Severity? severity,
          String? hint,
          String? url,
          String? fingerprint,
          String? Function()? snippet,
          List<TextEdit>? edits}) =>
      Finding(
        tool: tool,
        ruleId: ruleId,
        category: category ?? this.category,
        severity: severity ?? this.severity,
        line: line,
        column: column,
        message: message,
        snippet: snippet == null ? this.snippet : snippet(),
        equivalents: equivalents,
        hint: hint ?? this.hint,
        url: url ?? this.url,
        fingerprint: fingerprint ?? this.fingerprint,
        edits: edits ?? this.edits,
      );

  /// Relit un problème sérialisé par [toJson] (baseline, interface Flutter).
  factory Finding.fromJson(Map<String, Object?> j) => Finding(
        tool: '${j['tool']}',
        ruleId: '${j['rule']}',
        category: Category.tryParse('${j['category']}') ?? Category.robustness,
        severity: Severity.tryParse('${j['severity']}') ?? Severity.low,
        line: jsonInt(j['line']) ?? 0,
        column: jsonInt(j['column']) ?? 0,
        message: '${j['message']}',
        snippet: j['snippet'] as String?,
        hint: j['hint'] as String?,
        url: j['url'] as String?,
        fingerprint: j['fingerprint'] as String?,
        edits: [
          if (j['edits'] case final List l)
            for (final e in l.whereType<Map<String, Object?>>())
              TextEdit.fromJson(e, '${j['rule']}'),
        ],
      );

  Map<String, Object?> toJson() => {
        'tool': tool,
        'rule': ruleId,
        'category': category.name,
        'severity': severity.name,
        'line': line,
        'column': column,
        'message': message,
        if (snippet != null) 'snippet': snippet,
        if (hint != null) 'hint': hint,
        if (url != null) 'url': url,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (edits.isNotEmpty) 'edits': [for (final e in edits) e.toJson()],
      };

  @override
  String toString() =>
      '$tool:$ruleId ${category.name}/${severity.name} L$line $message';
}

/// Compte rendu d'exécution d'un outil pour un script.
class ToolRun {
  final String tool;
  final ToolStatus status;
  final String? version;

  /// Détail (message d'erreur, raison du saut…).
  final String? detail;
  final int findings;

  const ToolRun(this.tool, this.status,
      {this.version, this.detail, this.findings = 0});

  Map<String, Object?> toJson() => {
        'tool': tool,
        'status': status.name,
        if (version != null) 'version': version,
        if (detail != null) 'detail': detail,
        'findings': findings,
      };
}

enum ToolStatus { ok, missing, skipped, failed, disabled }
