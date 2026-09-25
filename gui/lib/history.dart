/// Historique des analyses d'un dossier : une entrée par analyse (date,
/// note moyenne, niveaux, note de chaque script), pour tracer l'évolution.
///
/// Emplacement : `${XDG_DATA_HOME:-~/.local/share}/check-script/history/`,
/// un fichier JSON par dossier analysé.
library;

import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
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
