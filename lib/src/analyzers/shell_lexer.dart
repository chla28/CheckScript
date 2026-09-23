/// Découpage léger d'un script en lignes « de code » : commentaires retirés,
/// corps de heredoc repérés, contenu des chaînes masqué pour l'analyse
/// structurelle. Ce n'est pas un parseur shell complet : il suffit aux règles
/// intégrées, qui sont heuristiques.
library;

class CodeLine {
  /// Numéro de ligne (1-based).
  final int number;
  final String raw;

  /// Ligne sans commentaire (vide pour un corps de heredoc).
  final String code;

  /// [code] dont le contenu des chaînes quotées et des `${…}` est remplacé par
  /// des espaces : sert à repérer mots-clés et accolades.
  final String bare;

  /// La ligne appartient au corps d'un heredoc.
  final bool inHeredoc;

  /// La ligne commence à l'intérieur d'une chaîne ouverte plus haut.
  final bool continuesString;

  const CodeLine(this.number, this.raw, this.code, this.bare,
      {this.inHeredoc = false, this.continuesString = false});
}

final _heredocStart =
    RegExp(r'''(?<!<)<<(-?)\s*(\\?)(['"]?)([A-Za-z_][\w-]*)\3''');

List<CodeLine> lexScript(List<String> lines) {
  final out = <CodeLine>[];
  // Heredocs en attente (plusieurs possibles sur une même ligne).
  final pending = <(String, bool)>[];
  String? quote; // ' ou " ouvert sur une ligne précédente
  var paramDepth = 0; // ${ … } ouverts

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    if (pending.isNotEmpty) {
      final (delim, dash) = pending.first;
      final candidate = dash ? raw.replaceFirst(RegExp(r'^\t+'), '') : raw;
      if (candidate == delim) pending.removeAt(0);
      out.add(CodeLine(i + 1, raw, '', '', inHeredoc: true));
      continue;
    }

    final continues = quote != null;
    final code = StringBuffer();
    final bare = StringBuffer();
    var j = 0;
    while (j < raw.length) {
      final ch = raw[j];
      if (quote == null) {
        if (ch == '\\' && j + 1 < raw.length) {
          code.write(raw.substring(j, j + 2));
          bare.write('  ');
          j += 2;
          continue;
        }
        if (ch == '#' &&
            paramDepth == 0 &&
            (j == 0 || RegExp(r'[\s;&|(]').hasMatch(raw[j - 1]))) {
          break; // commentaire jusqu'à la fin de ligne
        }
        if (ch == "'" || ch == '"') {
          quote = ch;
          code.write(ch);
          bare.write(ch);
          j++;
          continue;
        }
        if (ch == r'$' && j + 1 < raw.length && raw[j + 1] == '{') {
          paramDepth++;
          code.write(r'${');
          bare.write('  ');
          j += 2;
          continue;
        }
        if (ch == '}' && paramDepth > 0) {
          paramDepth--;
          code.write(ch);
          bare.write(' ');
          j++;
          continue;
        }
        code.write(ch);
        bare.write(paramDepth > 0 ? ' ' : ch);
        j++;
      } else {
        // Dans une chaîne : seul le guillemet fermant (non échappé) compte.
        if (quote == '"' && ch == '\\' && j + 1 < raw.length) {
          code.write(raw.substring(j, j + 2));
          bare.write('  ');
          j += 2;
          continue;
        }
        code.write(ch);
        if (ch == quote) {
          quote = null;
          bare.write(ch);
        } else {
          bare.write(' ');
        }
        j++;
      }
    }

    // code et bare ont la même longueur (substitution caractère à caractère).
    final codeStr = code.toString();
    final bareStr = bare.toString();
    for (final m in _heredocStart.allMatches(codeStr)) {
      // Ignore les << situés dans une chaîne (masqués dans bare).
      if (bareStr[m.start] != '<') continue;
      pending.add((m.group(4)!, m.group(1) == '-'));
    }
    out.add(CodeLine(i + 1, raw, codeStr, bareStr, continuesString: continues));
  }
  return out;
}
