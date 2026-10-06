/// Exclusion de chemins de l'analyse : motifs au format `.gitignore`
/// (option `--exclude`, clé `exclude` de la configuration, fichier
/// `.checkscriptignore` à la racine d'un dossier analysé).
library;

import 'dart:io';

/// Nom du fichier de motifs lu à la racine d'un dossier analysé.
const ignoreFileName = '.checkscriptignore';

/// Motifs d'exclusion, dans la syntaxe de `.gitignore` (sous-ensemble) :
///
/// - lignes vides et `# commentaire` ignorées ;
/// - `motif/` : seulement les dossiers ;
/// - un motif sans `/` (hors fin) s'applique à tout niveau, sinon il est
///   relatif à la racine ; `/motif` ancre explicitement à la racine ;
/// - `*` (sans `/`), `?`, `[abc]`, `**` (tout niveau) ;
/// - `!motif` réinclut ce qu'un motif précédent excluait (le dernier motif
///   qui correspond l'emporte), sauf sous un dossier exclu.
class IgnoreRules {
  IgnoreRules(Iterable<String> patterns) {
    for (final raw in patterns) {
      final rule = _Rule.parse(raw);
      if (rule != null) _rules.add(rule);
    }
  }

  /// Aucun motif.
  static final none = IgnoreRules(const []);

  final _rules = <_Rule>[];

  bool get isEmpty => _rules.isEmpty;

  /// Le chemin [relative] (relatif à la racine analysée, séparateur `/`)
  /// est exclu : lui-même, ou l'un de ses dossiers parents.
  /// [isDirectory] : le chemin est un dossier (motifs `motif/`).
  bool ignores(String relative, {bool isDirectory = false}) {
    if (_rules.isEmpty) return false;
    final parts = [
      for (final s in relative.replaceAll('\\', '/').split('/'))
        if (s.isNotEmpty && s != '.') s
    ];
    for (var i = 1; i <= parts.length; i++) {
      final dir = i < parts.length || isDirectory;
      if (_ignoredPrefix(parts.sublist(0, i).join('/'), dir)) return true;
    }
    return false;
  }

  bool _ignoredPrefix(String path, bool isDir) {
    var ignored = false;
    for (final r in _rules) {
      if (r.dirOnly && !isDir) continue;
      if (r.regex.hasMatch(path)) ignored = !r.negated;
    }
    return ignored;
  }

  /// Motifs d'un fichier `.checkscriptignore` (ou `.gitignore`) ; liste
  /// vide si le fichier est absent ou illisible.
  static List<String> readFile(String path) {
    try {
      return File(path).readAsLinesSync();
    } on FileSystemException {
      return const [];
    }
  }
}

class _Rule {
  _Rule(this.regex, {required this.negated, required this.dirOnly});

  final RegExp regex;
  final bool negated;
  final bool dirOnly;

  static _Rule? parse(String raw) {
    var line = raw.trimRight();
    if (line.isEmpty || line.startsWith('#')) return null;
    var negated = false;
    if (line.startsWith('!')) {
      negated = true;
      line = line.substring(1);
    } else if (line.startsWith(r'\!') || line.startsWith(r'\#')) {
      line = line.substring(1);
    }
    var dirOnly = false;
    if (line.endsWith('/')) {
      dirOnly = true;
      line = line.substring(0, line.length - 1);
    }
    if (line.isEmpty) return null;
    final anchored = line.contains('/');
    if (line.startsWith('/')) line = line.substring(1);
    final body = _glob(line);
    return _Rule(RegExp(anchored ? '^$body\$' : '^(?:.*/)?$body\$'),
        negated: negated, dirOnly: dirOnly);
  }

  /// Motif glob → expression régulière.
  static String _glob(String g) {
    final b = StringBuffer();
    var i = 0;
    while (i < g.length) {
      final c = g[i];
      if (c == '*') {
        if (i + 1 < g.length && g[i + 1] == '*') {
          // `**/` : zéro ou plusieurs dossiers ; `/**` final : tout le
          // contenu ; sinon, tout.
          if (i + 2 < g.length && g[i + 2] == '/') {
            b.write('(?:.*/)?');
            i += 3;
          } else {
            b.write('.*');
            i += 2;
          }
        } else {
          b.write('[^/]*');
          i++;
        }
      } else if (c == '?') {
        b.write('[^/]');
        i++;
      } else if (c == '[') {
        final end = g.indexOf(']', i + 2);
        if (end < 0) {
          b.write(r'\[');
          i++;
        } else {
          var set = g.substring(i + 1, end);
          if (set.startsWith('!')) set = '^${set.substring(1)}';
          b.write('[${set.replaceAll(r'\', r'\\')}]');
          i = end + 1;
        }
      } else if (c == r'\' && i + 1 < g.length) {
        b.write(RegExp.escape(g[i + 1]));
        i += 2;
      } else {
        b.write(RegExp.escape(c));
        i++;
      }
    }
    return b.toString();
  }
}
