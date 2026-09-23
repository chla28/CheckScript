/// Correction automatique (`--fix`) limitée aux transformations sûres :
///
/// 1. corrections proposées par ShellCheck (champ `fix` du JSON, ex. quoting) ;
/// 2. corrections intégrées : fins de ligne CRLF, espaces finaux, backticks →
///    `$(…)`, `egrep`/`fgrep` → `grep -E`/`-F`, `which` → `command -v`,
///    `read` → `read -r` ;
/// 3. formatage shfmt dans le style d'indentation du script.
///
/// Le résultat est contrôlé par `<shell> -n` : si le script était valide et ne
/// l'est plus, aucune correction n'est retenue.
library;

import 'dart:convert';
import 'dart:io';

import 'analyzers/analyzer.dart';
import 'analyzers/external_tools.dart';
import 'analyzers/shell_lexer.dart';
import 'analyzers/shellcheck.dart';
import 'config.dart';
import 'script_info.dart';

class FixResult {
  final String original;
  final String fixed;

  /// Corrections appliquées : identifiant → nombre d'occurrences.
  final Map<String, int> applied;

  /// Message si les corrections ont été abandonnées (syntaxe cassée).
  final String? aborted;

  const FixResult(this.original, this.fixed, this.applied, {this.aborted});

  bool get changed => fixed != original;
}

/// Remplacement ShellCheck (positions 1-based, fin exclusive, tabulation = 1).
class TextEdit {
  final int line, column, endLine, endColumn;
  final String replacement;
  final String rule;
  const TextEdit(this.line, this.column, this.endLine, this.endColumn,
      this.replacement, this.rule);
}

/// Extrait les remplacements proposés par ShellCheck (`-f json1`).
List<TextEdit> parseShellcheckFixes(String json) {
  if (json.trim().isEmpty) return const [];
  final doc = jsonDecode(json);
  final comments = doc is Map ? doc['comments'] : doc;
  if (comments is! List) return const [];
  final out = <TextEdit>[];
  for (final c in comments.whereType<Map>()) {
    final fix = c['fix'];
    if (fix is! Map || fix['replacements'] is! List) continue;
    for (final r in (fix['replacements'] as List).whereType<Map>()) {
      out.add(TextEdit(
        (r['line'] as num).toInt(),
        (r['column'] as num).toInt(),
        (r['endLine'] as num).toInt(),
        (r['endColumn'] as num).toInt(),
        '${r['replacement']}',
        'SC${c['code']}',
      ));
    }
  }
  return out;
}

/// Applique des remplacements sans chevauchement (les suivants en conflit
/// sont ignorés). Renvoie le texte et le nombre d'éditions par règle.
(String, Map<String, int>) applyEdits(String text, List<TextEdit> edits) {
  final lines = text.split('\n');
  final starts = <int>[];
  var off = 0;
  for (final l in lines) {
    starts.add(off);
    off += l.length + 1;
  }
  int pos(int line, int col) {
    final i = (line - 1).clamp(0, lines.length - 1);
    return starts[i] + (col - 1).clamp(0, lines[i].length);
  }

  final spans = [
    for (final e in edits)
      (pos(e.line, e.column), pos(e.endLine, e.endColumn), e)
  ]..sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2));
  final kept = <(int, int, TextEdit)>[];
  var lastEnd = -1;
  for (final s in spans) {
    // Deux insertions au même point sont compatibles (ex. "…" autour d'un mot).
    if (s.$1 < lastEnd) continue;
    kept.add(s);
    if (s.$2 > lastEnd) lastEnd = s.$2;
  }
  final counts = <String, int>{};
  var out = text;
  for (final s in kept.reversed) {
    out = out.replaceRange(s.$1, s.$2, s.$3.replacement);
  }
  // Une correction ShellCheck = un commentaire, même en plusieurs éditions.
  final perComment = <String>{};
  for (final s in kept) {
    perComment.add('${s.$3.rule}@${s.$3.line}');
  }
  for (final k in perComment) {
    final rule = k.split('@').first;
    counts[rule] = (counts[rule] ?? 0) + 1;
  }
  return (out, counts);
}

const _cmdPrefix =
    r'(^\s*|[;&|({]\s*|\$\(\s*|\b(?:then|do|else|if|while|until|!)\s+)';

/// Corrections intégrées, ligne par ligne, hors corps de heredoc et hors
/// chaînes multi-lignes.
(String, Map<String, int>) applyBuiltinFixes(String text) {
  final counts = <String, int>{};
  void count(String id, [int n = 1]) {
    if (n > 0) counts[id] = (counts[id] ?? 0) + n;
  }

  final lines = text.split('\n');
  final lexed = lexScript(lines);
  final egrep = RegExp('$_cmdPrefix([ef])grep\\b');
  final which = RegExp('${_cmdPrefix}which(\\s)');
  final read =
      RegExp('$_cmdPrefix((?:IFS=\\S*\\s+)?)read\\b(?![^;|&]*\\s-[a-zA-Z]*r)');

  for (var i = 0; i < lines.length && i < lexed.length; i++) {
    final l = lexed[i];
    if (l.inHeredoc || l.continuesString) continue;
    var line = lines[i];

    final trimmed = line.replaceFirst(RegExp(r'[ \t]+$'), '');
    if (trimmed != line) {
      count('MNT010');
      line = trimmed;
    }
    // Les motifs s'appliquent au code (commentaires retirés) : on ne
    // transforme que la partie code de la ligne.
    final codeLen = l.code.length <= line.length ? l.code.length : line.length;
    var code = line.substring(0, codeLen);
    final rest = line.substring(codeLen);

    code = code.replaceAllMapped(egrep, (m) {
      count('POR005');
      return '${m[1]}grep -${m[2] == 'e' ? 'E' : 'F'}';
    });
    code = code.replaceAllMapped(which, (m) {
      count('POR004');
      return '${m[1]}command -v${m[2]}';
    });
    code = code.replaceAllMapped(read, (m) {
      count('ROB007');
      return '${m[1]}${m[2]}read -r';
    });
    final (bt, n) = replaceBackticks(code);
    count('MNT007', n);
    lines[i] = bt + rest;
  }
  return (lines.join('\n'), counts);
}

/// Remplace les substitutions `…` simples (sans antislash ni backtick
/// imbriqué) hors apostrophes par $(…).
(String, int) replaceBackticks(String code) {
  final b = StringBuffer();
  var n = 0;
  var inSingle = false, inDouble = false;
  var i = 0;
  while (i < code.length) {
    final c = code[i];
    if (c == '\\' && !inSingle && i + 1 < code.length) {
      b.write(code.substring(i, i + 2));
      i += 2;
      continue;
    }
    if (c == "'" && !inDouble) inSingle = !inSingle;
    if (c == '"' && !inSingle) inDouble = !inDouble;
    if (c == '`' && !inSingle) {
      final end = code.indexOf('`', i + 1);
      if (end > i + 1) {
        final inner = code.substring(i + 1, end);
        if (!inner.contains('\\')) {
          b.write('\$($inner)');
          n++;
          i = end + 1;
          continue;
        }
      }
    }
    b.write(c);
    i++;
  }
  return (b.toString(), n);
}

/// Corrige un script. [filePath] sert de nom dans les messages ; le contenu
/// passé aux outils est toujours [script.content].
Future<FixResult> fixScript(ScriptInfo script,
    {CheckConfig config = const CheckConfig(),
    CommandRunner runner = const ProcessCommandRunner()}) async {
  final applied = <String, int>{};
  void merge(Map<String, int> m) =>
      m.forEach((k, v) => applied[k] = (applied[k] ?? 0) + v);

  var text = script.content;
  if (script.hasCrlf) applied['ROB009'] = 1; // déjà normalisé par ScriptInfo

  // 1. ShellCheck (sur un fichier temporaire : ShellCheck lit les fichiers).
  final sc = config.tool('shellcheck');
  if (sc.enabled) {
    final tmp = await Directory.systemTemp.createTemp('check_script_fix_');
    try {
      final f = File('${tmp.path}/script.sh');
      await f.writeAsString(text);
      final r = await runner.run(sc.executable, [
        '--format=json1',
        '--enable=${ShellcheckAnalyzer.optionalChecks.join(',')}',
        if (sc.exclude.isNotEmpty) '--exclude=${sc.exclude.join(',')}',
        if (script.dialect.shellcheckName != null)
          '--shell=${script.dialect.shellcheckName}',
        f.path,
      ]);
      if (r != null && r.stdout.trim().isNotEmpty) {
        final (t, c) = applyEdits(text, parseShellcheckFixes(r.stdout));
        text = t;
        merge(c);
      }
    } on FormatException {
      // Sortie inexploitable : on passe aux corrections suivantes.
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  // 2. Corrections intégrées.
  final (t2, c2) = applyBuiltinFixes(text);
  text = t2;
  merge(c2);

  // 3. Formatage shfmt.
  final sf = config.tool('shfmt');
  if (sf.enabled && script.dialect != Dialect.zsh) {
    final ln = script.dialect.shfmtName ?? 'auto';
    final r = await runner.run(
        sf.executable, ['-ln=$ln', '-i=${indentUnit(text.split('\n'))}'],
        stdin: text);
    if (r != null &&
        r.exitCode == 0 &&
        r.stdout.isNotEmpty &&
        r.stdout != text) {
      text = r.stdout;
      applied['FORMAT'] = 1;
    }
  }

  if (!text.endsWith('\n') && script.content.endsWith('\n')) text = '$text\n';

  // Contrôle : ne jamais rendre invalide un script qui était valide.
  if (text != script.content && config.tool('syntax').enabled) {
    final shell = SyntaxAnalyzer.interpreterFor(script.dialect);
    final before = await runner.run(shell, ['-n'], stdin: script.content);
    final after = await runner.run(shell, ['-n'], stdin: text);
    if (before != null &&
        after != null &&
        before.exitCode == 0 &&
        after.exitCode != 0) {
      return FixResult(script.content, script.content, const {},
          aborted: after.stderr.trim());
    }
  }
  return FixResult(script.content, text, applied);
}
