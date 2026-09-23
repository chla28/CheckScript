/// Modèle de base : catégories, sévérités et problèmes détectés.
library;

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
  });

  Finding copyWith({Category? category, Severity? severity}) => Finding(
        tool: tool,
        ruleId: ruleId,
        category: category ?? this.category,
        severity: severity ?? this.severity,
        line: line,
        column: column,
        message: message,
        snippet: snippet,
        equivalents: equivalents,
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
