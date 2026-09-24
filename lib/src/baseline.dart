/// Référence (baseline) : un rapport JSON antérieur, comparé à l'analyse
/// courante pour ne signaler que les nouveaux problèmes et suivre l'évolution
/// des notes.
///
/// Les problèmes sont appariés par empreinte : outil + règle + contenu
/// normalisé de la ligne + rang d'occurrence. L'empreinte ne dépend pas du
/// numéro de ligne : ajouter du code au-dessus d'un problème connu ne le fait
/// pas passer pour nouveau.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'model/finding.dart';
import 'model/report.dart';
import 'json_num.dart';

/// FNV-1a 64 bits (hexadécimal) : empreinte courte et stable, sans
/// dépendance cryptographique (ce n'est pas un usage de sécurité).
String fnv1a64(String input) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final b in utf8.encode(input)) {
    hash = ((hash ^ BigInt.from(b)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Ajoute leur empreinte aux problèmes d'un script.
List<Finding> fingerprintAll(List<Finding> findings, List<String> lines) {
  final seen = <String, int>{};
  return [
    for (final f in findings)
      () {
        final content = f.line >= 1 && f.line <= lines.length
            ? lines[f.line - 1].trim().replaceAll(RegExp(r'\s+'), ' ')
            : '';
        final key = '${f.tool}|${f.ruleId}|$content';
        final n = seen[key] = (seen[key] ?? 0) + 1;
        return f.copyWith(fingerprint: fnv1a64('$key|$n'));
      }(),
  ];
}

class BaselineEntry {
  final String file;
  final Map<String, int> fingerprints;
  final double global;
  final Map<Category, double> scores;
  const BaselineEntry(this.file, this.fingerprints, this.global, this.scores);
}

class Baseline {
  final List<BaselineEntry> entries;
  const Baseline(this.entries);

  /// Lit un rapport JSON de check-script. Lève [FormatException] s'il n'en
  /// est pas un.
  factory Baseline.parse(String json) {
    final Object? doc;
    try {
      doc = jsonDecode(json);
    } on FormatException {
      throw const FormatException('référence : JSON invalide');
    }
    if (doc is! Map || doc['reports'] is! List) {
      throw const FormatException(
          'référence : rapport JSON de check-script attendu (clé "reports")');
    }
    return Baseline([
      for (final r in (doc['reports'] as List).whereType<Map>())
        BaselineEntry(
          '${r['file']}',
          () {
            final m = <String, int>{};
            for (final f
                in (r['findings'] as List? ?? const []).whereType<Map>()) {
              final fp = f['fingerprint'];
              if (fp is String) m[fp] = (m[fp] ?? 0) + 1;
            }
            return m;
          }(),
          jsonDouble((r['global'] as Map?)?['score']) ?? 0,
          {
            for (final c
                in (r['categories'] as List? ?? const []).whereType<Map>())
              if (Category.tryParse('${c['category']}') != null)
                Category.tryParse('${c['category']}')!:
                    jsonDouble(c['score']) ?? 0,
          },
        ),
    ]);
  }

  /// Entrée correspondant à un script : même chemin, sinon même nom de
  /// fichier s'il est unique dans la référence.
  BaselineEntry? entryFor(String path) {
    for (final e in entries) {
      if (e.file == path || p.normalize(e.file) == p.normalize(path)) return e;
    }
    final same = entries.where((e) => p.basename(e.file) == p.basename(path));
    return same.length == 1 ? same.first : null;
  }

  /// Compare un rapport à la référence ; null si le script n'y figure pas.
  Comparison? compare(ScriptReport report) {
    final e = entryFor(report.script.path);
    if (e == null) return null;
    final remaining = Map<String, int>.of(e.fingerprints);
    final added = <Finding>[];
    var unchanged = 0;
    for (final f in report.findings) {
      final n = remaining[f.fingerprint] ?? 0;
      if (f.fingerprint != null && n > 0) {
        remaining[f.fingerprint!] = n - 1;
        unchanged++;
      } else {
        added.add(f);
      }
    }
    return Comparison(
      added: added,
      fixed: remaining.values.fold(0, (a, b) => a + b),
      unchanged: unchanged,
      previousGlobal: e.global,
      previousScores: e.scores,
    );
  }
}
