/// Anomalies : constats **informatifs**, à côté des problèmes. Elles ne
/// changent ni la note ni les seuils : une corrélation de signaux ou la
/// suggestion d'un modèle n'a pas la certitude d'une règle.
library;

/// Origine d'une anomalie.
enum AnomalyKind {
  /// Combinaison de comportements dans un même script.
  behaviour,

  /// Écart par rapport aux autres scripts analysés.
  outlier,

  /// Changement depuis la référence.
  drift,

  /// Suggestion d'un modèle de langage local.
  model;

  static AnomalyKind parse(String s) =>
      values.firstWhere((k) => k.name == s, orElse: () => behaviour);
}

enum AnomalyLevel {
  high,
  medium,
  low;

  static AnomalyLevel parse(String s) =>
      values.firstWhere((l) => l.name == s.toLowerCase(), orElse: () => low);
}

class Anomaly {
  /// `AB…` comportement, `AF…` parc, `AD…` dérive, `AI…` modèle.
  final String id;
  final AnomalyKind kind;
  final AnomalyLevel level;
  final String title;
  final String detail;

  /// Lignes qui justifient le constat (vide : tout le script).
  final List<int> lines;

  const Anomaly(this.id, this.kind, this.level, this.title, this.detail,
      [this.lines = const []]);

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'level': level.name,
        'title': title,
        'detail': detail,
        if (lines.isNotEmpty) 'lines': lines,
      };

  factory Anomaly.fromJson(Map<String, Object?> j) => Anomaly(
        '${j['id']}',
        AnomalyKind.parse('${j['kind']}'),
        AnomalyLevel.parse('${j['level']}'),
        '${j['title']}',
        '${j['detail']}',
        [
          for (final l in j['lines'] as List? ?? const []) (l as num).toInt(),
        ],
      );
}

/// Ce qu'un script « sait faire » : sert à comparer les scripts d'un parc et
/// une analyse à la référence.
class AnomalyProfile {
  final Set<String> capabilities;
  final Set<String> hosts;
  final Set<String> commands;

  const AnomalyProfile(
      {this.capabilities = const {},
      this.hosts = const {},
      this.commands = const {}});

  Map<String, Object?> toJson() => {
        'capabilities': capabilities.toList()..sort(),
        'hosts': hosts.toList()..sort(),
        'commands': commands.toList()..sort(),
      };

  /// Null si [j] n'est pas un profil (référence produite sans anomalies).
  static AnomalyProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    Set<String> set(Object? v) =>
        {for (final e in v is List ? v : const []) '$e'};
    return AnomalyProfile(
      capabilities: set(j['capabilities']),
      hosts: set(j['hosts']),
      commands: set(j['commands']),
    );
  }
}
