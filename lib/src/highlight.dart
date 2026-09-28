/// Coloration syntaxique légère (interface graphique) : découpe chaque ligne
/// en jetons typés, pour le shell, Python et les fichiers hôtes des scripts
/// intégrés (YAML, Dockerfile, Makefile). Les constructions sur plusieurs
/// lignes (heredocs, chaînes, chaînes triples de Python) sont suivies d'une
/// ligne à l'autre.
library;

import 'embedded.dart';
import 'script_info.dart';

enum TokenKind {
  comment,
  string,
  keyword,
  builtin,
  variable,
  number,
  operator,
  function,

  /// Clé YAML, instruction de Dockerfile, cible de Makefile.
  key,
  shebang,
}

/// Jeton : colonnes [start, end[ (0-based) d'une ligne.
class Token {
  final int start, end;
  final TokenKind kind;
  const Token(this.start, this.end, this.kind);

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;
  @override
  int get hashCode => Object.hash(start, end, kind);
  @override
  String toString() => '$kind[$start,$end[';
}

enum HighlightLanguage {
  shell,
  python,
  yaml,
  dockerfile,
  makefile;

  /// Langage d'affichage d'un script (fichier hôte compris).
  static HighlightLanguage of(ScriptInfo s) => switch (s.embedded?.kind) {
        EmbeddedKind.githubActions ||
        EmbeddedKind.gitlabCi ||
        EmbeddedKind.ansible =>
          yaml,
        EmbeddedKind.dockerfile => dockerfile,
        EmbeddedKind.makefile => makefile,
        null => s.dialect.isPython ? python : shell,
      };
}

/// Jetons de chaque ligne (le texte hors jeton est ordinaire).
List<List<Token>> highlightLines(List<String> lines, HighlightLanguage lang) {
  final out = <List<Token>>[];
  switch (lang) {
    case HighlightLanguage.shell:
      final sh = _Shell();
      for (var i = 0; i < lines.length; i++) {
        out.add(sh.line(lines[i], first: i == 0));
      }
    case HighlightLanguage.python:
      final py = _Python();
      for (var i = 0; i < lines.length; i++) {
        out.add(py.line(lines[i], first: i == 0));
      }
    case HighlightLanguage.yaml:
      out.addAll(lines.map(_yaml));
    case HighlightLanguage.dockerfile:
      final sh = _Shell();
      var continued = false;
      for (final l in lines) {
        out.add(_dockerfile(l, sh, continued));
        final t = l.trimLeft();
        if (!t.startsWith('#')) continued = l.trimRight().endsWith('\\');
      }
    case HighlightLanguage.makefile:
      final sh = _Shell();
      for (final l in lines) {
        out.add(l.startsWith('\t') ? _recipe(l, sh) : _make(l));
      }
  }
  return out;
}

bool _isWord(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);

// ── Shell ───────────────────────────────────────────────────────────────────

const _shKeywords = {
  'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done', //
  'case', 'esac', 'in', 'function', 'select', 'time', 'return', 'exit',
  'break', 'continue', 'local', 'export', 'readonly', 'declare', 'typeset',
};

const _shBuiltins = {
  'echo', 'printf', 'read', 'cd', 'pwd', 'test', 'set', 'unset', 'shift', //
  'source', 'trap', 'eval', 'exec', 'exit', 'wait', 'kill', 'command',
  'type', 'getopts', 'umask', 'alias', 'unalias', 'let', 'mapfile',
  'readarray', 'pushd', 'popd', 'true', 'false', 'shopt', 'hash', 'ulimit',
};

class _Shell {
  /// Heredoc ouvert : délimiteur et `<<-` (tabulations ignorées).
  String? _heredoc;
  bool _stripTabs = false;
  final _pending = <(String, bool)>[];

  /// Chaîne ouverte d'une ligne précédente (`"` ou `'`).
  String? _quote;

  /// Dans un heredoc ou une chaîne commencés plus haut.
  bool get inside => _heredoc != null || _quote != null;

  List<Token> line(String l, {bool first = false}) {
    final out = <Token>[];
    if (_heredoc != null) {
      final t = _stripTabs ? l.replaceFirst(RegExp(r'^\t+'), '') : l;
      out.add(Token(0, l.length, TokenKind.string));
      if (t == _heredoc) {
        out
          ..clear()
          ..add(Token(0, l.length, TokenKind.operator));
        _heredoc = null;
        _next();
      }
      return out;
    }
    if (first && l.startsWith('#!')) {
      return [Token(0, l.length, TokenKind.shebang)];
    }
    var i = 0;
    var command = true; // position de commande (début, après ; | && …)
    if (_quote != null) {
      i = _string(l, 0, _quote!, out);
    }
    while (i < l.length) {
      final c = l[i];
      if (c == ' ' || c == '\t') {
        i++;
        continue;
      }
      if (c == '#' && (i == 0 || RegExp(r'[\s;|&(]').hasMatch(l[i - 1]))) {
        out.add(Token(i, l.length, TokenKind.comment));
        break;
      }
      if (c == '"' || c == "'") {
        i = _string(l, i + 1, c, out, open: i);
        command = false;
        continue;
      }
      if (c == r'$') {
        final end = _variable(l, i);
        if (end > i + 1) {
          out.add(Token(i, end, TokenKind.variable));
          i = end;
          command = false;
          continue;
        }
      }
      final here = RegExp(r'''<<(-?)\s*(["']?)([A-Za-z_][\w-]*)\2''')
          .matchAsPrefix(l, i);
      if (here != null) {
        out.add(Token(i, here.end, TokenKind.operator));
        _pending.add((here[3]!, here[1] == '-'));
        i = here.end;
        continue;
      }
      final op = RegExp(r'\|\||&&|;;|[|;&<>(){}]|\[\[|\]\]|>>|\$\(')
          .matchAsPrefix(l, i);
      if (op != null) {
        out.add(Token(i, op.end, TokenKind.operator));
        final o = op[0]!;
        command = o != '>' && o != '>>' && o != '<' && o != ')' && o != '}';
        i = op.end;
        continue;
      }
      // Mot.
      var j = i;
      while (j < l.length && !RegExp(r'''[\s;|&<>(){}"'$`]''').hasMatch(l[j])) {
        j++;
      }
      if (j == i) {
        i++;
        continue;
      }
      final w = l.substring(i, j);
      final assign = RegExp(r'^[A-Za-z_]\w*(?=\+?=)').firstMatch(w);
      if (command && assign != null) {
        out.add(Token(i, i + assign.end, TokenKind.variable));
      } else if (command && _shKeywords.contains(w)) {
        out.add(Token(i, j, TokenKind.keyword));
        // Après ces mots-clés, on reste en position de commande.
        command = true;
        i = j;
        continue;
      } else if (command && RegExp(r'^\s*\(\s*\)').hasMatch(l.substring(j))) {
        out.add(Token(i, j, TokenKind.function));
      } else if (command && _shBuiltins.contains(w)) {
        out.add(Token(i, j, TokenKind.builtin));
      } else if (RegExp(r'^-?\d+$').hasMatch(w)) {
        out.add(Token(i, j, TokenKind.number));
      }
      command = assign != null && command;
      i = j;
    }
    if (_pending.isNotEmpty && _heredoc == null) _next();
    return out;
  }

  void _next() {
    if (_pending.isEmpty) return;
    final (word, strip) = _pending.removeAt(0);
    _heredoc = word;
    _stripTabs = strip;
  }

  /// Fin d'une expansion `$…` commençant en [i] (i + 1 : pas de variable).
  static int _variable(String l, int i) {
    if (i + 1 >= l.length) return i + 1;
    final n = l[i + 1];
    if (n == '{') {
      final close = l.indexOf('}', i + 2);
      return close < 0 ? l.length : close + 1;
    }
    if (RegExp(r'[0-9@*#?$!-]').hasMatch(n)) return i + 2;
    var j = i + 1;
    while (j < l.length && _isWord(l[j])) {
      j++;
    }
    return j;
  }

  /// Chaîne jusqu'au guillemet [q] (variables colorées entre `"`) ; renvoie
  /// la position suivante. Une chaîne non fermée continue à la ligne
  /// suivante.
  int _string(String l, int i, String q, List<Token> out, {int? open}) {
    var start = open ?? i;
    var j = i;
    while (j < l.length) {
      final c = l[j];
      if (c == '\\' && q == '"') {
        j += 2;
        continue;
      }
      if (c == q) {
        out.add(Token(start, j + 1, TokenKind.string));
        _quote = null;
        return j + 1;
      }
      if (c == r'$' && q == '"') {
        final end = _variable(l, j);
        if (end > j + 1) {
          if (j > start) out.add(Token(start, j, TokenKind.string));
          out.add(Token(j, end, TokenKind.variable));
          start = j = end;
          continue;
        }
      }
      j++;
    }
    if (l.length > start) out.add(Token(start, l.length, TokenKind.string));
    _quote = q;
    return l.length;
  }
}

// ── Python ──────────────────────────────────────────────────────────────────

const _pyKeywords = {
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', //
  'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except',
  'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda',
  'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while',
  'with', 'yield', 'match', 'case',
};

const _pyBuiltins = {
  'print', 'len', 'range', 'open', 'str', 'int', 'float', 'bool', 'list', //
  'dict', 'set', 'tuple', 'type', 'isinstance', 'enumerate', 'zip', 'map',
  'filter', 'sorted', 'sum', 'min', 'max', 'abs', 'any', 'all', 'input',
  'super', 'self', 'cls', 'Exception', 'ValueError', 'KeyError',
  'TypeError', 'OSError', 'RuntimeError', 'ImportError', 'object', 'bytes',
  'repr', 'hasattr', 'getattr', 'setattr', 'iter', 'next', 'format',
};

class _Python {
  /// Chaîne triple ouverte (`"""` ou `'''`).
  String? _triple;

  List<Token> line(String l, {bool first = false}) {
    final out = <Token>[];
    if (first && l.startsWith('#!')) {
      return [Token(0, l.length, TokenKind.shebang)];
    }
    var i = 0;
    if (_triple != null) {
      final end = l.indexOf(_triple!);
      if (end < 0) return [Token(0, l.length, TokenKind.string)];
      out.add(Token(0, end + 3, TokenKind.string));
      _triple = null;
      i = end + 3;
    }
    var afterDef = false;
    while (i < l.length) {
      final c = l[i];
      if (c == '#') {
        out.add(Token(i, l.length, TokenKind.comment));
        break;
      }
      final str = RegExp(r'''(?:[rRbBuUfF]{1,2})?("""|\'\'\'|"|')''')
          .matchAsPrefix(l, i);
      if (str != null && (i == 0 || !_isWord(l[i - 1]))) {
        final q = str[1]!;
        var j = str.end;
        var closed = false;
        while (j < l.length) {
          if (l[j] == '\\') {
            j += 2;
            continue;
          }
          if (l.startsWith(q, j)) {
            j += q.length;
            closed = true;
            break;
          }
          j++;
        }
        if (j > l.length) j = l.length;
        out.add(Token(i, j, TokenKind.string));
        if (!closed && q.length == 3) _triple = q;
        i = j;
        continue;
      }
      if (c == '@' && l.substring(0, i).trim().isEmpty) {
        final m = RegExp(r'@[\w.]+').matchAsPrefix(l, i)!;
        out.add(Token(i, m.end, TokenKind.function));
        i = m.end;
        continue;
      }
      if (_isWord(c)) {
        var j = i;
        while (j < l.length && _isWord(l[j])) {
          j++;
        }
        final w = l.substring(i, j);
        if (afterDef) {
          out.add(Token(i, j, TokenKind.function));
          afterDef = false;
        } else if (_pyKeywords.contains(w)) {
          out.add(Token(i, j, TokenKind.keyword));
          afterDef = w == 'def' || w == 'class';
        } else if (_pyBuiltins.contains(w)) {
          out.add(Token(i, j, TokenKind.builtin));
        } else if (RegExp(r'^\d').hasMatch(w)) {
          out.add(Token(i, j, TokenKind.number));
        }
        i = j;
        continue;
      }
      i++;
    }
    return out;
  }
}

// ── Fichiers hôtes ──────────────────────────────────────────────────────────

final _expr = RegExp(r'\$\{\{.*?\}\}|\{\{.*?\}\}|\{%.*?%\}');

List<Token> _yaml(String l) {
  final out = <Token>[];
  final t = l.trimLeft();
  if (t.startsWith('#')) {
    return [Token(l.length - t.length, l.length, TokenKind.comment)];
  }
  final key =
      RegExp(r'^(\s*(?:-\s+)?)([\w.$/-]+|"[^"]*"|' "'[^']*'" r')\s*:(?=\s|$)')
          .firstMatch(l);
  var from = 0;
  if (key != null) {
    out.add(
        Token(key[1]!.length, key[1]!.length + key[2]!.length, TokenKind.key));
    from = key.end;
  }
  final rest = l.substring(from);
  // Commentaire de fin de ligne (hors chaîne, précédé d'un blanc).
  final comment = RegExp(r'''\s#''').firstMatch(rest);
  final end = comment == null ? l.length : from + comment.start + 1;
  for (final m in RegExp(r'"(?:\\.|[^"\\])*"' "|'(?:''|[^'])*'")
      .allMatches(l.substring(0, end), from)) {
    out.add(Token(m.start, m.end, TokenKind.string));
  }
  for (final m in _expr.allMatches(l.substring(0, end), from)) {
    out.add(Token(m.start, m.end, TokenKind.variable));
  }
  final v = RegExp(r'^\s*(true|false|null|~|-?\d+(?:\.\d+)?|[|>][-+]?)\s*$')
      .firstMatch(rest);
  if (v != null) {
    final s = from + rest.indexOf(v[1]!);
    out.add(Token(
        s,
        s + v[1]!.length,
        v[1]!.startsWith('|') || v[1]!.startsWith('>')
            ? TokenKind.operator
            : TokenKind.number));
  }
  if (comment != null) out.add(Token(end, l.length, TokenKind.comment));
  return _sorted(out);
}

List<Token> _dockerfile(String l, _Shell sh, bool continued) {
  if (sh.inside) return sh.line(l); // corps d'un heredoc (RUN <<EOF)
  final t = l.trimLeft();
  if (t.startsWith('#')) {
    return [Token(l.length - t.length, l.length, TokenKind.comment)];
  }
  if (continued) return sh.line(l);
  final m = RegExp(r'^(\s*)([A-Za-z]+)\b').firstMatch(l);
  if (m == null) return sh.line(l);
  final start = m[1]!.length;
  final rest = sh.line(' ' * m.end + l.substring(m.end));
  return [Token(start, m.end, TokenKind.key), ...rest];
}

List<Token> _make(String l) {
  final t = l.trimLeft();
  if (t.startsWith('#')) {
    return [Token(l.length - t.length, l.length, TokenKind.comment)];
  }
  final out = <Token>[];
  final directive = RegExp(
          r'^\s*(ifeq|ifneq|ifdef|ifndef|else|endif|include|-include|define|endef|export|override)\b')
      .firstMatch(l);
  if (directive != null) {
    out.add(Token(directive.start + directive[0]!.indexOf(directive[1]!),
        directive.end, TokenKind.keyword));
  } else {
    final assign =
        RegExp(r'^\s*([A-Za-z_][\w.-]*)\s*(?:[:?+!]?=)').firstMatch(l);
    final rule = RegExp(r'^([^\s#=:][^=]*?)::?(?!=)').firstMatch(l);
    if (assign != null) {
      final s = assign.start + assign[0]!.indexOf(assign[1]!);
      out.add(Token(s, s + assign[1]!.length, TokenKind.variable));
    } else if (rule != null) {
      out.add(Token(0, rule[1]!.length, TokenKind.function));
    }
  }
  for (final m in _makeRef.allMatches(l)) {
    out.add(Token(m.start, m.end, TokenKind.variable));
  }
  final c = RegExp(r'\s#').firstMatch(l);
  if (c != null) out.add(Token(c.start + 1, l.length, TokenKind.comment));
  return _sorted(out);
}

final _makeRef = RegExp(r'\$[({][^)}]*[)}]|\$[@<^*?%]');

/// Recette de Makefile : du shell, avec les références de make (`$(CC)`,
/// `$@`), `$$` pour `$` et les préfixes `@ - +`.
List<Token> _recipe(String l, _Shell sh) {
  final prefix = RegExp(r'^\t[@+\-\s]*').firstMatch(l)!.end;
  final refs = _makeRef.allMatches(l).toList();
  var text = ' ' * prefix + l.substring(prefix);
  for (final m in refs) {
    text = text.replaceRange(m.start, m.end, 'x' * (m.end - m.start));
  }
  text = text.replaceAll(r'$$', r' $');
  return _sorted([
    for (final m in refs) Token(m.start, m.end, TokenKind.variable),
    ...sh
        .line(text)
        .where((t) => !refs.any((m) => t.start < m.end && m.start < t.end)),
  ]);
}

/// Jetons triés et sans chevauchement (le premier l'emporte).
List<Token> _sorted(List<Token> tokens) {
  tokens.sort((a, b) => a.start.compareTo(b.start));
  final out = <Token>[];
  var end = 0;
  for (final t in tokens) {
    if (t.start < end || t.end <= t.start) continue;
    out.add(t);
    end = t.end;
  }
  return out;
}
