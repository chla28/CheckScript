/// Correction automatique (`--fix`) limitée aux transformations sûres :
///
/// 1. corrections proposées par ShellCheck (champ `fix` du JSON, ex. quoting) ;
/// 2. corrections intégrées : fins de ligne CRLF, espaces finaux, backticks →
///    `$(…)`, `egrep`/`fgrep` → `grep -E`/`-F`, `which` → `command -v`,
///    `read` → `read -r` ;
/// 3. formatage shfmt dans le style d'indentation du script.
///
/// Pour un script Python : corrections sûres de `ruff check --fix`, puis
/// `ruff format`.
///
/// Le résultat est contrôlé par `<shell> -n` (ou la compilation Python) : si
/// le script était valide et ne l'est plus, aucune correction n'est retenue.
library;

import 'dart:convert';
import 'dart:io';

import 'analyzers/analyzer.dart';
import 'analyzers/external_tools.dart';
import 'analyzers/python_tools.dart';
import 'analyzers/shell_lexer.dart';
import 'analyzers/shellcheck.dart';
import 'config.dart';
import 'i18n.dart';
import 'script_info.dart';
import 'json_num.dart';
import 'model/finding.dart';

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
        jsonInt(r['line'])!,
        jsonInt(r['column'])!,
        jsonInt(r['endLine'])!,
        jsonInt(r['endColumn'])!,
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

final _egrep = RegExp('$_cmdPrefix([ef])grep\\b');
final _which = RegExp('${_cmdPrefix}which(\\s)');
final _read =
    RegExp('$_cmdPrefix((?:IFS=\\S*\\s+)?)read\\b(?![^;|&]*\\s-[a-zA-Z]*r)');

/// Corrections intégrées portant sur la partie code d'une ligne
/// (commentaire exclu) : règle → transformation (texte, occurrences).
final Map<String, (String, int) Function(String)> _codeFixes = {
  'POR005': (code) {
    var n = 0;
    final out = code.replaceAllMapped(_egrep, (m) {
      n++;
      return '${m[1]}grep -${m[2] == 'e' ? 'E' : 'F'}';
    });
    return (out, n);
  },
  'POR004': (code) {
    var n = 0;
    final out = code.replaceAllMapped(_which, (m) {
      n++;
      return '${m[1]}command -v${m[2]}';
    });
    return (out, n);
  },
  'ROB007': (code) {
    var n = 0;
    final out = code.replaceAllMapped(_read, (m) {
      n++;
      return '${m[1]}${m[2]}read -r';
    });
    return (out, n);
  },
  'MNT007': replaceBackticks,
};

/// Codes ShellCheck corrigés par une correction intégrée.
const Map<String, String> _builtinFixAliases = {
  'SC2196': 'POR005',
  'SC2197': 'POR005',
  'SC2230': 'POR004',
  'SC2162': 'ROB007',
  'SC2006': 'MNT007',
};

/// Applique à une ligne les corrections intégrées retenues par [only]
/// (toutes si null) ; les occurrences sont comptées dans [count].
String _fixLine(CodeLine l, String line, void Function(String, int) count,
    {String? only, bool Function(String id)? skip}) {
  bool wanted(String id) =>
      (only == null || only == id) && !(skip?.call(id) ?? false);
  if (wanted('MNT010')) {
    final trimmed = line.replaceFirst(RegExp(r'[ \t]+$'), '');
    if (trimmed != line) {
      count('MNT010', 1);
      line = trimmed;
    }
  }
  // Les motifs s'appliquent au code (commentaires retirés) : on ne
  // transforme que la partie code de la ligne.
  final codeLen = l.code.length <= line.length ? l.code.length : line.length;
  var code = line.substring(0, codeLen);
  final rest = line.substring(codeLen);
  for (final MapEntry(key: id, value: fix) in _codeFixes.entries) {
    if (!wanted(id)) continue;
    final (out, n) = fix(code);
    count(id, n);
    code = out;
  }
  return code + rest;
}

/// Corrections intégrées, ligne par ligne, hors corps de heredoc et hors
/// chaînes multi-lignes.
/// Les règles pour lesquelles [skip] est vrai (désactivées) sont ignorées.
(String, Map<String, int>) applyBuiltinFixes(String text,
    {bool Function(String id)? skip}) {
  final counts = <String, int>{};
  void count(String id, int n) {
    if (n > 0) counts[id] = (counts[id] ?? 0) + n;
  }

  final lines = text.split('\n');
  final lexed = lexScript(lines);
  for (var i = 0; i < lines.length && i < lexed.length; i++) {
    final l = lexed[i];
    if (l.inHeredoc || l.continuesString) continue;
    lines[i] = _fixLine(l, lines[i], count, skip: skip);
  }
  return (lines.join('\n'), counts);
}

/// Joint à chaque problème sans correction ShellCheck la correction intégrée
/// de sa règle, limitée à sa ligne. Les lignes masquées (secret potentiel,
/// [Finding.snippet] absent) ne reçoivent jamais de correction. Les
/// corrections intégrées ne concernent que le shell ([shell] faux : Python).
List<Finding> attachFixes(List<Finding> findings, List<String> lines,
    {bool shell = true}) {
  if (!shell) return findings;
  final lexed = lexScript(lines);
  return [
    for (final f in findings)
      () {
        final rule = _builtinFixAliases[f.ruleId] ?? f.ruleId;
        if (f.edits.isNotEmpty ||
            f.snippet == null ||
            f.line < 1 ||
            f.line > lexed.length ||
            (rule != 'MNT010' && !_codeFixes.containsKey(rule))) {
          return f;
        }
        final l = lexed[f.line - 1];
        if (l.inHeredoc || l.continuesString) return f;
        final before = lines[f.line - 1];
        final after = _fixLine(l, before, (_, __) {}, only: rule);
        if (after == before) return f;
        return f.copyWith(edits: [
          TextEdit(f.line, 1, f.line, before.length + 1, after, f.ruleId)
        ]);
      }(),
  ];
}

/// Aperçu de la correction d'un problème : lignes concernées avant et après
/// (première ligne, texte avant, texte après), ou null sans correction.
(int, String, String)? fixPreview(Finding f, List<String> lines) {
  if (f.edits.isEmpty) return null;
  var first = lines.length, last = 1;
  for (final e in f.edits) {
    if (e.line < first) first = e.line;
    if (e.endLine > last) last = e.endLine;
  }
  if (first < 1 || last > lines.length || first > last) return null;
  final before = lines.sublist(first - 1, last).join('\n');
  final (after, _) = applyEdits(before, [
    for (final e in f.edits)
      TextEdit(e.line - first + 1, e.column, e.endLine - first + 1, e.endColumn,
          e.replacement, e.rule)
  ]);
  return after == before ? null : (first, before, after);
}

/// Message d'erreur si [fixed] casse la syntaxe d'un script qui était valide
/// (contrôle `<shell> -n` ou compilation Python), sinon null.
Future<String?> syntaxRegression(ScriptInfo script, String fixed,
    {CheckConfig config = const CheckConfig(),
    CommandRunner runner = const ProcessCommandRunner()}) async {
  if (fixed == script.content || !config.tool('syntax').enabled) return null;
  final (exe, args) = SyntaxAnalyzer.commandFor(script.dialect);
  final before = await runner.run(exe, args, stdin: script.content);
  final after = await runner.run(exe, args, stdin: fixed);
  if (before != null &&
      after != null &&
      before.exitCode == 0 &&
      after.exitCode != 0) {
    return after.stderr.trim();
  }
  return null;
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
  // Fichier hôte (Dockerfile, CI…) : pas de réécriture automatique.
  if (script.embedded != null) {
    return FixResult(script.content, script.content, const {});
  }
  final r = script.dialect.isPython
      ? await _fixPython(script, config: config, runner: runner)
      : await _fixShell(script, config: config, runner: runner);
  if (r.aborted != null) return r;
  // Remplacements des règles personnalisées, en dernier.
  final (text, counts) = applyCustomFixes(
      ScriptInfo.fromContent(script.path, r.fixed,
          forcedDialect: script.dialect),
      config);
  if (counts.isEmpty) return r;
  final broken =
      await syntaxRegression(script, text, config: config, runner: runner);
  if (broken != null) return r;
  return FixResult(r.original, text, {...r.applied, ...counts});
}

/// Applique les remplacements des règles personnalisées (non désactivées)
/// à [script] ; renvoie le texte et le nombre de corrections par règle.
(String, Map<String, int>) applyCustomFixes(
    ScriptInfo script, CheckConfig config) {
  final edits = [
    for (final rule in config.customRules)
      if (rule.replace != null && !config.isRuleDisabled(rule.id))
        for (final f in rule.check(script, Lang.en)) ...f.edits,
  ];
  if (edits.isEmpty) return (script.content, const {});
  return applyEdits(script.content, edits);
}

Future<FixResult> _fixShell(ScriptInfo script,
    {required CheckConfig config, required CommandRunner runner}) async {
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
        if (config.excludedFor('shellcheck') case final ex when ex.isNotEmpty)
          '--exclude=${ex.join(',')}',
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
  final (t2, c2) = applyBuiltinFixes(text, skip: config.isRuleDisabled);
  text = t2;
  merge(c2);

  // 3. Formatage shfmt.
  final sf = config.tool('shfmt');
  if (sf.enabled &&
      !config.isRuleDisabled('FORMAT') &&
      script.dialect != Dialect.zsh) {
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
  final broken =
      await syntaxRegression(script, text, config: config, runner: runner);
  if (broken != null) {
    return FixResult(script.content, script.content, const {}, aborted: broken);
  }
  return FixResult(script.content, text, applied);
}

/// Corrections d'un script Python par Ruff, sur l'entrée standard : les
/// corrections sûres de `ruff check --fix` (comptées d'après la sortie JSON),
/// puis `ruff format`.
Future<FixResult> _fixPython(ScriptInfo script,
    {required CheckConfig config, required CommandRunner runner}) async {
  final ruff = config.tool('ruff');
  if (!ruff.enabled) return FixResult(script.content, script.content, const {});
  const stdinName = '--stdin-filename=script.py';
  final applied = <String, int>{};
  var text = script.content;

  final check = RuffAnalyzer.checkArgs(config, scriptPath: script.path);
  final listed = await runner.run(
      ruff.executable, [...check, '--output-format=json', stdinName, '-'],
      stdin: text);
  if (listed != null && listed.exitCode <= 1) {
    try {
      for (final f in parseRuff(listed.stdout)) {
        if (f.edits.isNotEmpty && !config.isRuleDisabled(f.ruleId)) {
          applied[f.ruleId] = (applied[f.ruleId] ?? 0) + 1;
        }
      }
    } on FormatException {
      applied.clear();
    }
    if (applied.isNotEmpty) {
      final r = await runner.run(
          ruff.executable,
          // Codes relevés par Ruff lui-même (donc valides), hors règles
          // désactivées.
          [
            ...check,
            '--fix',
            '--fixable=${applied.keys.join(',')}',
            stdinName,
            '-'
          ],
          stdin: text);
      if (r != null && r.exitCode <= 1 && r.stdout.isNotEmpty) {
        text = r.stdout;
      } else {
        applied.clear();
      }
    }
  }

  final fmt = config.isRuleDisabled('FORMAT')
      ? null
      : await runner.run(
          ruff.executable,
          [
            'format',
            ...RuffAnalyzer.commonArgs(config, scriptPath: script.path),
            stdinName,
            '-'
          ],
          stdin: text);
  if (fmt != null &&
      fmt.exitCode == 0 &&
      fmt.stdout.isNotEmpty &&
      fmt.stdout != text) {
    text = fmt.stdout;
    applied['FORMAT'] = 1;
  }

  final broken =
      await syntaxRegression(script, text, config: config, runner: runner);
  if (broken != null) {
    return FixResult(script.content, script.content, const {}, aborted: broken);
  }
  return FixResult(script.content, text, applied);
}

/// Texte reformaté de [script] (shfmt pour le shell, `ruff format` pour
/// Python), ou null : outil absent ou désactivé, erreur de syntaxe, texte
/// déjà formaté, fichier hôte (Dockerfile, CI…). Pour « Formater le
/// document » d'un éditeur : aucune autre correction n'est appliquée.
Future<String?> formatScript(ScriptInfo script,
    {CheckConfig config = const CheckConfig(),
    CommandRunner runner = const ProcessCommandRunner()}) async {
  if (script.embedded != null) return null;
  final text = script.content;
  final CommandResult? r;
  if (script.dialect.isPython) {
    final ruff = config.tool('ruff');
    if (!ruff.enabled) return null;
    r = await runner.run(
        ruff.executable,
        [
          'format',
          ...RuffAnalyzer.commonArgs(config, scriptPath: script.path),
          '--stdin-filename=script.py',
          '-'
        ],
        stdin: text);
  } else {
    final sf = config.tool('shfmt');
    if (!sf.enabled || script.dialect == Dialect.zsh) return null;
    r = await runner.run(
        sf.executable,
        [
          '-ln=${script.dialect.shfmtName ?? 'auto'}',
          '-i=${indentUnit(script.lines)}'
        ],
        stdin: text);
  }
  if (r == null || r.exitCode != 0 || r.stdout.isEmpty || r.stdout == text) {
    return null;
  }
  return r.stdout;
}
