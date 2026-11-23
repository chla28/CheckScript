/// Historique des analyses d'un dossier : une entrée par analyse (date,
/// note moyenne, niveaux, note de chaque script), pour tracer l'évolution.
///
/// Emplacement : `${XDG_DATA_HOME:-~/.local/share}/check-script/history/`,
/// un fichier JSON par dossier analysé.
library;

import 'dart:convert';
import 'dart:io';

import 'model/report.dart';
import 'result_cache.dart' show fastHash;
import 'package:path/path.dart' as p;

class HistoryEntry {
  final DateTime date;
  final double average;
  final int scripts;
  final Map<String, int> grades;

  /// Note globale par script (chemin relatif au dossier).
  final Map<String, double> scores;

  const HistoryEntry(
      this.date, this.average, this.scripts, this.grades, this.scores);

  /// Entrée résumant [reports] (analyse du dossier [folder]).
  factory HistoryEntry.of(String folder, List<ScriptReport> reports,
      {DateTime? date}) {
    final grades = <String, int>{};
    for (final r in reports) {
      grades[r.grade] = (grades[r.grade] ?? 0) + 1;
    }
    return HistoryEntry(
      date ?? DateTime.now(),
      reports.isEmpty
          ? 0
          : ((reports.map((r) => r.global).reduce((a, b) => a + b) /
                          reports.length) *
                      10)
                  .round() /
              10,
      reports.length,
      grades,
      {
        for (final r in reports)
          p.relative(r.script.path, from: folder): r.global
      },
    );
  }

  Map<String, Object?> toJson() => {
        'date': date.toIso8601String(),
        'average': average,
        'scripts': scripts,
        'grades': grades,
        'scores': scores,
      };

  static HistoryEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return HistoryEntry(
        DateTime.parse('${j['date']}'),
        (j['average'] as num).toDouble(),
        (j['scripts'] as num).toInt(),
        {
          for (final e in (j['grades'] as Map? ?? const {}).entries)
            '${e.key}': (e.value as num).toInt()
        },
        {
          for (final e in (j['scores'] as Map? ?? const {}).entries)
            '${e.key}': (e.value as num).toDouble()
        },
      );
    } on Object {
      return null;
    }
  }
}

class FolderHistory {
  FolderHistory(this.dir);

  final Directory dir;

  /// Nombre d'analyses conservées par dossier.
  static const maxEntries = 200;

  static FolderHistory? standard() {
    final env = Platform.environment;
    final base = env['XDG_DATA_HOME'] ??
        (env['HOME'] == null ? null : '${env['HOME']}/.local/share');
    return base == null
        ? null
        : FolderHistory(Directory('$base/check-script/history'));
  }

  File _file(String folder) =>
      File('${dir.path}/${fastHash(p.normalize(p.absolute(folder)))}.json');

  /// Analyses enregistrées pour [folder], de la plus ancienne à la plus
  /// récente.
  Future<List<HistoryEntry>> load(String folder) async {
    try {
      final f = _file(folder);
      if (!await f.exists()) return [];
      final j = jsonDecode(await f.readAsString());
      return [
        for (final e in (j is Map ? j['entries'] as List? : null) ?? const [])
          if (HistoryEntry.fromJson(e) case final h?) h
      ];
    } on Object {
      return [];
    }
  }

  /// Ajoute [entry] et renvoie l'historique à jour.
  Future<List<HistoryEntry>> append(String folder, HistoryEntry entry) async {
    final all = [...await load(folder), entry];
    final kept =
        all.length > maxEntries ? all.sublist(all.length - maxEntries) : all;
    try {
      await dir.create(recursive: true);
      await _file(folder).writeAsString(jsonEncode({
        'folder': p.normalize(p.absolute(folder)),
        'entries': [for (final e in kept) e.toJson()],
      }));
    } on FileSystemException {
      // Historique non inscriptible : ignoré.
    }
    return kept;
  }
}

/// Historique en CSV : une ligne par analyse (date, note moyenne, nombre de
/// scripts, effectif de chaque niveau A à E).
String historyCsv(List<HistoryEntry> entries) {
  final b = StringBuffer('date,average,scripts,A,B,C,D,E\n');
  for (final e in entries) {
    b.writeln([
      e.date.toIso8601String(),
      e.average,
      e.scripts,
      for (final g in const ['A', 'B', 'C', 'D', 'E']) e.grades[g] ?? 0,
    ].join(','));
  }
  return b.toString();
}

/// Historique en CSV « long » : une ligne par analyse et par script (date,
/// script, note), pour suivre un script dans le temps.
String historyScriptsCsv(List<HistoryEntry> entries) {
  String q(String s) =>
      s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  final b = StringBuffer('date,script,score\n');
  for (final e in entries) {
    for (final s in e.scores.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      b.writeln('${e.date.toIso8601String()},${q(s.key)},${s.value}');
    }
  }
  return b.toString();
}

/// Scripts dont la note a le plus évolué entre la première et la dernière
/// analyse : (script, note initiale, note finale), triés du plus fort recul
/// au plus fort progrès. Les scripts absents de l'une des deux sont écartés.
List<(String, double, double)> scoreChanges(List<HistoryEntry> entries) {
  if (entries.length < 2) return const [];
  final first = entries.first.scores, last = entries.last.scores;
  final out = [
    for (final e in last.entries)
      if (first[e.key] != null && first[e.key] != e.value)
        (e.key, first[e.key]!, e.value)
  ]..sort((a, b) => (a.$3 - a.$2).compareTo(b.$3 - b.$2));
  return out;
}
