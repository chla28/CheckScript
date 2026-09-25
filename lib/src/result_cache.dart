/// Cache des résultats d'analyse : un script dont ni le contenu, ni la
/// configuration, ni les versions des outils n'ont changé n'est pas
/// réanalysé (dossiers relancés, CI, pre-commit).
///
/// Emplacement : `${XDG_CACHE_HOME:-~/.cache}/check-script/results/`.
library;

import 'dart:convert';
import 'dart:io';

import 'model/report.dart';
import 'script_info.dart';

/// Empreinte FNV-1a 64 bits (entiers natifs, arithmétique modulo 2⁶⁴).
String fastHash(String input) {
  var h = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final b in utf8.encode(input)) {
    h = (h ^ b) * prime;
  }
  // Deux moitiés de 32 bits : un entier signé ne s'écrit pas en hexadécimal
  // non signé directement.
  return (h >>> 32).toRadixString(16).padLeft(8, '0') +
      (h & 0xffffffff).toRadixString(16).padLeft(8, '0');
}

class ResultCache {
  ResultCache(this.dir);

  final Directory dir;

  /// Durée de conservation d'une entrée non relue.
  static const maxAge = Duration(days: 30);

  static Directory? defaultDir() {
    final env = Platform.environment;
    final base = env['XDG_CACHE_HOME'] ??
        (env['HOME'] == null ? null : '${env['HOME']}/.cache');
    return base == null ? null : Directory('$base/check-script/results');
  }

  /// Cache par défaut, ou null si aucun emplacement n'est connu.
  static ResultCache? standard() {
    final d = defaultDir();
    return d == null ? null : ResultCache(d);
  }

  File _file(String key) => File('${dir.path}/$key.json');

  /// Rapport enregistré pour [key], reconstruit pour [script] ; null s'il
  /// est absent ou illisible.
  ScriptReport? read(String key, ScriptInfo script) {
    final f = _file(key);
    try {
      if (!f.existsSync()) return null;
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map<String, Object?>) return null;
      // Relu : l'entrée reste fraîche.
      f.setLastModifiedSync(DateTime.now());
      return ScriptReport.fromJson(j, script);
    } on Object {
      return null;
    }
  }

  /// Enregistre [report] (écriture atomique ; erreurs ignorées : le cache
  /// n'est qu'une accélération).
  Future<void> write(String key, ScriptReport report) async {
    try {
      await dir.create(recursive: true);
      final tmp = File('${dir.path}/$key.$pid.tmp');
      await tmp.writeAsString(jsonEncode(report.toJson()));
      await tmp.rename(_file(key).path);
    } on FileSystemException {
      // Cache non inscriptible : ignoré.
    }
  }

  /// Retire les entrées plus vieilles que [maxAge].
  Future<void> prune() async {
    try {
      if (!await dir.exists()) return;
      final limit = DateTime.now().subtract(maxAge);
      await for (final e in dir.list()) {
        if (e is File && (await e.lastModified()).isBefore(limit)) {
          await e.delete();
        }
      }
    } on FileSystemException {
      // Ignoré.
    }
  }
}
