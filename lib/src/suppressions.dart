/// Directives de suppression écrites dans le script lui-même :
///
/// ```sh
/// # check-script disable-file=MNT005,E003     ← tout le fichier
/// # check-script disable=SEC022               ← ligne suivante (commentaire seul)
/// curl -k "$URL"  # check-script disable=SEC005   ← cette ligne
/// ```
///
/// Les identifiants acceptent le joker final `*` (`SC20*`) et `all`.
/// Les directives `# shellcheck disable=…` restent traitées par ShellCheck.
///
/// Dans un script Python, les directives natives valent pour tous les
/// outils : `# noqa` (toute la ligne), `# noqa: E722,F401` (ces codes),
/// `# nosec` (problèmes de sécurité de la ligne), `# nosec B602` (ce code) ;
/// un code vise aussi la même règle dans les autres outils ([sameRuleIds]).
library;

import 'model/finding.dart';
import 'rules/same_rules.dart';

final _noqa = RegExp(
    r'#\s*noqa\b(?:\s*:\s*([A-Za-z]+\d+(?:[\s,]+[A-Za-z]+\d+)*))?',
    caseSensitive: false);
final _nosec = RegExp(r'#\s*nosec\b(?:[\s:]+([Bb]\d{3}(?:[\s,]+[Bb]\d{3})*))?');

final _directive = RegExp(
    r'#\s*check-script\s+(disable|disable-file|disable-next-line)\s*=\s*([\w*,\s-]+)',
    caseSensitive: false);

class Suppressions {
  /// Règles supprimées pour tout le fichier.
  final Set<String> file;

  /// Règles supprimées par ligne (1-based).
  final Map<int, Set<String>> lines;

  /// Lignes où les problèmes de sécurité sont supprimés (`# nosec`).
  final Set<int> security;

  const Suppressions(this.file, this.lines, [this.security = const {}]);

  static const none = Suppressions({}, {});

  bool get isEmpty => file.isEmpty && lines.isEmpty && security.isEmpty;

  /// [python] : prend aussi en compte `# noqa` et `# nosec`.
  factory Suppressions.parse(List<String> scriptLines, {bool python = false}) {
    final file = <String>{};
    final lines = <int, Set<String>>{};
    final security = <int>{};
    Set<String> withSame(String codes) => {
          for (final c in codes.split(RegExp(r'[\s,]+')))
            if (c.isNotEmpty) ...{c.toUpperCase(), ...sameRuleIds(c)}
        };
    for (var i = 0; i < scriptLines.length; i++) {
      final raw = scriptLines[i];
      if (python) {
        final q = _noqa.firstMatch(raw);
        if (q != null) {
          (lines[i + 1] ??= <String>{})
              .addAll(q.group(1) == null ? {'ALL'} : withSame(q.group(1)!));
        }
        final s = _nosec.firstMatch(raw);
        if (s != null) {
          if (s.group(1) == null) {
            security.add(i + 1);
          } else {
            (lines[i + 1] ??= <String>{}).addAll(withSame(s.group(1)!));
          }
        }
      }
      final m = _directive.firstMatch(raw);
      if (m == null) continue;
      final ids = {
        for (final id in m.group(2)!.split(RegExp(r'[,\s]+')))
          if (id.trim().isNotEmpty) id.trim().toUpperCase()
      };
      final kind = m.group(1)!.toLowerCase();
      if (kind == 'disable-file') {
        file.addAll(ids);
        continue;
      }
      final commentOnly = raw.trimLeft().startsWith('#');
      var target = i + 1; // ligne courante (1-based)
      if (commentOnly || kind == 'disable-next-line') {
        // Prochaine ligne qui n'est ni vide ni un commentaire.
        var j = i + 1;
        while (j < scriptLines.length &&
            (scriptLines[j].trim().isEmpty ||
                scriptLines[j].trimLeft().startsWith('#'))) {
          j++;
        }
        target = j + 1;
      }
      (lines[target] ??= <String>{}).addAll(ids);
    }
    return Suppressions(file, lines, security);
  }

  static bool _matches(String pattern, String id) {
    if (pattern == 'ALL') return true;
    return pattern.endsWith('*')
        ? id.startsWith(pattern.substring(0, pattern.length - 1))
        : pattern == id;
  }

  bool suppresses(Finding f) {
    final id = f.ruleId.toUpperCase();
    if (file.any((p) => _matches(p, id))) return true;
    if (f.category == Category.security && security.contains(f.line)) {
      return true;
    }
    final l = lines[f.line];
    return l != null && l.any((p) => _matches(p, id));
  }
}
