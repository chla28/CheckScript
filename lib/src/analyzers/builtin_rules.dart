/// Règles intégrées (Dart) : toujours disponibles, elles couvrent les points
/// que les outils externes ne traitent pas (secrets, téléchargements exécutés,
/// permissions, structure du code…) et assurent une analyse minimale quand
/// aucun outil externe n'est installé.
///
/// Le classement et les textes des règles sont dans `rules/catalog.dart`.
/// Chaque détection déclare ses `equivalents` (codes ShellCheck, bashate…) :
/// si un autre outil a signalé la même chose sur la même ligne, le doublon est
/// supprimé par le moteur.
///
/// Quand l'arbre syntaxique de shfmt est disponible ([AstFacts]), les règles
/// structurelles et celles qui portent sur un nom de commande l'utilisent ;
/// sinon, elles retombent sur le découpage heuristique de `shell_lexer.dart`.
library;

import 'dart:math' as math;

import '../config.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../rules/catalog.dart';
import '../script_info.dart';
import 'analyzer.dart';
import 'ast.dart';
import 'shell_lexer.dart';

export '../rules/catalog.dart' show RuleInfo, allBuiltinRules, ExecContext;

/// Préfixe « position de commande » : début de ligne ou après un séparateur.
const _cmd =
    r'(?:^\s*|[;&|({]\s*|\$\(\s*|`\s*|\b(?:then|do|else|if|while|until|!)\s+)';

/// Détection ligne par ligne d'une règle du catalogue.
class LineRule {
  final String id;
  final RegExp pattern;
  final List<String> equivalents;

  /// Applique la règle au texte brut de la ligne (commentaires et heredocs
  /// compris) plutôt qu'au code nettoyé.
  final bool onRaw;

  /// Condition d'application au script (dialecte…).
  final bool Function(ScriptInfo s)? when;

  /// Filtre supplémentaire sur une correspondance.
  final bool Function(RegExpMatch m, CodeLine l)? accept;

  /// Ne pas recopier la ligne dans le rapport (secrets).
  final bool hideSnippet;

  /// Applique la règle à la ligne dont le contenu des chaînes est masqué :
  /// pour les règles sur un nom de commande (un « sudo » cité dans un
  /// message n'est pas une commande).
  final bool onBare;

  /// Règle portant sur un nom de commande : remplacée par sa version fondée
  /// sur l'arbre syntaxique quand celui-ci est disponible.
  final bool astCovered;

  LineRule(this.id, String re,
      {this.equivalents = const [],
      this.onRaw = false,
      this.when,
      this.accept,
      this.hideSnippet = false,
      this.onBare = false,
      this.astCovered = false,
      bool caseSensitive = true})
      : pattern = RegExp(re, caseSensitive: caseSensitive);

  RuleInfo get info => ruleInfo(id);
}

bool _posix(ScriptInfo s) => s.dialect.isPosix;
bool _bashLike(ScriptInfo s) =>
    s.dialect == Dialect.bash ||
    s.dialect == Dialect.ksh ||
    s.dialect == Dialect.zsh;
bool _setsPath(ScriptInfo s) =>
    RegExp(r'(?:^\s*|[;&]\s*|\bexport\s+)PATH=(?!\$PATH\b)', multiLine: true)
        .hasMatch(s.content);

final List<LineRule> lineRules = [
  // ── Sécurité ──────────────────────────────────────────────────────────────
  LineRule(
      'SEC001',
      r'\b(?:curl|wget|fetch)\b[^|;&]*\|\s*(?:sudo\s+(?:-\S+\s+)*)?(?:env\s+)?(?:/(?:usr/)?bin/)?(?:ba|da|z|k)?sh\b'
          r'|\b(?:(?:ba|da|z|k)?sh|source|\.)\s+(?:-c\s+)?["\x27]?(?:<\(|\$\()\s*(?:curl|wget)\b'),
  LineRule('SEC002',
      r'''(?:^|[\s;])(?:export\s+|local\s+|readonly\s+|declare\s+(?:-\w+\s+)*)?[A-Za-z_]*(?:pass(?:word|wd)?|secret|token|api_?key|access_?key|private_?key|credential)s?(?<!_(?:file|path|dir|url|name|len|length|min|max|prompt|var|env|cmd|type|id))=(['"]?)(?![$`(])[^'"\s]{4,}\1(?:\s|;|$)''',
      caseSensitive: false, hideSnippet: true),
  LineRule('SEC002',
      r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{36}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}',
      onRaw: true, hideSnippet: true),
  LineRule('SEC003', '${_cmd}eval\\s+.*[\$`]', astCovered: true),
  LineRule('SEC004',
      r'\bchmod\s+(?:-\w+\s+)*(?:0*[0-7]?[0-7][0-7][2367]|[ugoa]*[oa][ugoa]*[+=][rwxXst]*w)\b'),
  LineRule(
      'SEC005',
      r'\bcurl\b[^|;]*\s(?:--insecure|-[a-zA-Z]*k[a-zA-Z]*)\b|--no-check-certificate'
          r'|StrictHostKeyChecking[= ]+no\b|UserKnownHostsFile[= ]+/dev/null'
          r'|sslVerify\s*=?\s*false|GIT_SSL_NO_VERIFY=|--trusted-host\b',
      caseSensitive: false),
  LineRule('SEC006',
      r'\b(?:curl|wget|git\s+clone)\b[^|;]*\bhttp://(?!localhost\b|127\.|\[::1\])'),
  // Variable suivie d'un « / » (rm -rf "$DIR/…" → rm -rf /… si vide) ou
  // variable non quotée.
  LineRule('SEC007',
      r'\brm\s+(?:-\w+\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\b.*(?:\$\{?[A-Za-z_]\w*\}?"?/|\s\$\{?[A-Za-z_]\w*\}?(?=\s|;|$))',
      equivalents: ['SC2115', 'SC2114'],
      accept: (m, l) => !RegExp(r'\$\{[A-Za-z_]\w*:\?').hasMatch(l.code)),
  LineRule('SEC008',
      r'\brm\s+(?:-\w+\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\s+(?:--no-preserve-root\s+)?["\x27]?/(?:\*|(?:bin|boot|etc|home|lib|lib64|opt|root|sbin|srv|usr|var)/?\*?)?["\x27]?(?:\s|;|$)',
      equivalents: ['SC2114', 'SC2115']),
  LineRule('SEC009',
      r'''(?:>>?\s*|\b(?:tee|touch)\s+(?:-\w+\s+)*)["']?/(?:var/)?tmp/[A-Za-z0-9_.${}-]+'''),
  LineRule('SEC010',
      r'\becho\b.*\|\s*sudo\s+(?:-\w+\s+)*-S\b|\bsshpass\s+-p|\bmysql(?:dump|admin)?\b.*\s-p[^\s-]|--password[= ]\S',
      hideSnippet: true),
  LineRule(
      'SEC011', '$_cmd(?:source|\\.)\\s+["\']?(?:/tmp/|/var/tmp/|https?://)'),
  LineRule('SEC012', '${_cmd}set\\s+(?:-[a-wyzA-Z]*x|-o\\s+xtrace)\\b',
      astCovered: true, onBare: true),
  LineRule('SEC013',
      r'\bchmod\s+(?:-\w+\s+)*(?:[ugoa]*\+[rwxX]*s|0*[2467][0-7]{3})\b'),
  LineRule('SEC014',
      r'\bread\b(?![^;|&]*\s-[a-zA-Z]*s)[^;|&]*\b(?:pass(?:word|wd)?|secret|token|pin)\b',
      caseSensitive: false),
  LineRule('SEC015', '${_cmd}sudo\\s+(?:-[a-zA-Z]+\\s+)*(?![/-])[A-Za-z]',
      when: (s) => !_setsPath(s), onBare: true),
  LineRule(
      'SEC016', r'''(?:^|[\s;])(?:export\s+)?PATH=("[^"]*"|'[^']*'|[^\s;]+)''',
      accept: (m, l) {
    final v = m.group(1)!.replaceAll(RegExp(r'''^["']|["']$'''), '');
    return v.split(':').any((c) => c.isEmpty || c == '.');
  }),
  LineRule('SEC018',
      r'''(?:>>?\s*|\btee\s+(?:-a\s+)?)["']?\S*(?:/etc/sudoers|authorized_keys|/etc/passwd\b|/etc/shadow\b|/etc/crontab|/etc/cron\.d/)'''),
  LineRule('SEC019',
      r'\b(?:curl|wget)\b[^|;]*\|\s*(?:sudo\s+)?(?:tar|unzip|bsdtar|cpio)\b'),
  LineRule('SEC020',
      r'\b(?:ssh|scp|sftp)\b.*(?:\s-[a-zA-Z]*A\b|ForwardAgent[= ]+yes|PermitLocalCommand[= ]+yes)'),
  LineRule('SEC021',
      r'\bexport\s+[A-Z_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|CREDENTIALS?)[A-Z_0-9]*(?:=|\s|;|$)',
      equivalents: ['SEC002'], hideSnippet: true),

  // ── Robustesse ────────────────────────────────────────────────────────────
  LineRule('ROB005', '${_cmd}cd(?:\\s+[^;&|]*)?\\s*\$',
      equivalents: ['SC2164'],
      when: (s) => !_hasErrexit(s),
      astCovered: true,
      onBare: true),
  LineRule('ROB006',
      r'(?:^|\s)\[\s+\$\{?\w+\}?\s+(?:==?|!=|-(?:eq|ne|lt|gt|le|ge))\s',
      equivalents: ['SC2086']),
  LineRule('ROB007', '$_cmd(?:IFS=\\S*\\s+)?read\\b(?![^;|&]*\\s-[a-zA-Z]*r)',
      equivalents: ['SC2162'], astCovered: true, onBare: true),
  LineRule('ROB008', r'\bfor\s+\w+\s+in\s+(?:\$\(|`)\s*ls\b',
      equivalents: ['SC2045']),
  LineRule('ROB010', r'(?<!["\w$\\])\$[@*](?![\w"])',
      equivalents: ['SC2068', 'SC2048']),
  LineRule('ROB011',
      r'^\s*(?:mkdir|cp|mv|rm|tar|chown|chmod|ln|install|rsync)\s(?!.*(?:\|\||&&))',
      when: (s) => !_hasErrexit(s) && s.codeLines >= 5, astCovered: true),
  // Affectation globale d'IFS à une valeur littérale (une affectation depuis
  // une variable est une restauration).
  LineRule('ROB012', r'^\s*IFS=(?!"?\$\{?\w)\S*\s*(?:;|$)', when: (s) {
    return !RegExp(r'unset\s+IFS|IFS="?\$\{?\w|IFS=\$\x27').hasMatch(s.content);
  }),
  LineRule('ROB013',
      r'''(?:^\s*|[;&]\s*)trap\s+(?:'[^']+'|"[^"]+"|[^\s'"]+)\s+((?:SIG)?(?:INT|TERM|HUP|QUIT|ERR)(?:\s+(?:SIG)?\w+)*)\s*$''',
      accept: (m, l) => !RegExp(r'\b(?:EXIT|0)\b').hasMatch(m.group(1)!)),

  // ── Maintenabilité ────────────────────────────────────────────────────────
  LineRule('MNT006', r'#.*\b(?:TODO|FIXME|XXX|HACK)\b', onRaw: true),
  LineRule('MNT007', r'`[^`]+`', equivalents: ['SC2006']),
  LineRule('MNT010', r'[ \t]+$', onRaw: true, equivalents: ['E001']),

  // ── Portabilité ───────────────────────────────────────────────────────────
  LineRule(
      'POR003',
      r'\[\[|(?:^|[;&]\s*)function\s+\w+|\[\s[^\]]*\s==\s|\$'
          r"'"
          r'|\b\w+=\(|'
          '$_cmd'
          r'source\s|<<<|&>|\$\{\w+:-?\d|\$\{\w+//?[^}]|\becho\s+-[neE]+\s|\(\(|\blet\s|\b(?:declare|typeset)\b|\$(?:RANDOM|BASH_\w+|PIPESTATUS)\b|\bselect\s+\w+\s+in\b',
      when: _posix,
      equivalents: ['SC3*', 'SC2039', 'SC2112', 'SC2113', 'CB', 'DIALECT']),
  LineRule('POR004', '${_cmd}which\\s',
      equivalents: ['SC2230'], astCovered: true, onBare: true),
  LineRule('POR005', '$_cmd[ef]grep\\b',
      equivalents: ['SC2196', 'SC2197'], astCovered: true, onBare: true),
  LineRule('POR007', '$_cmd(?:ifconfig|netstat|route|arp|iwconfig)\\b',
      astCovered: true, onBare: true),

  // ── Performance ───────────────────────────────────────────────────────────
  LineRule('PERF001', '${_cmd}cat\\s+"?[^\\s|;&<>(-][^\\s|;&<>]*"?\\s*\\|',
      equivalents: ['SC2002']),
  LineRule('PERF002', r'\bgrep\b[^|]*\|\s*wc\s+-l\b', equivalents: ['SC2126']),
  LineRule('PERF003', '${_cmd}expr\\s',
      equivalents: ['SC2003'], astCovered: true, onBare: true),
  LineRule(
      'PERF005', r'\bgrep\b[^|]*\|\s*(?:grep|awk)\b|\bsed\b[^|]*\|\s*sed\b'),
  LineRule('PERF006', r'\bps\b[^|]*\|\s*grep\b', equivalents: ['SC2009']),
  LineRule('PERF007', r'\bfor\s+\w+\s+in\s+(?:\$\(|`)\s*seq\b',
      when: _bashLike),
  LineRule('PERF008', r'''\$\(\s*echo\s+["']?\$\{?\w+\}?["']?\s*\)''',
      equivalents: ['SC2116']),
  LineRule('PERF009', r'\$\(\s*cat\s+[^|;&)]+\)', when: _bashLike),
];

/// Le script active l'option `set -<letter>` / `set -o <longName>` (dans une
/// commande `set` ou dans les options du shebang).
bool _hasSetOption(ScriptInfo s, String letter, String longName) =>
    RegExp('(?:^\\s*|[;&]\\s*)set\\b[^;&|\\n#]*\\s(?:-[a-zA-Z]*$letter[a-zA-Z]*\\b|-o\\s+$longName\\b)',
            multiLine: true)
        .hasMatch(s.content) ||
    RegExp('\\s-[a-zA-Z]*$letter').hasMatch(s.shebang ?? '');

bool _hasErrexit(ScriptInfo s) => _hasSetOption(s, 'e', 'errexit');

class BuiltinAnalyzer extends Analyzer {
  @override
  String get name => 'builtin';

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final ast = await loadAst(ctx);
    final findings =
        runBuiltinRules(ctx.script, ctx.config, ctx.lang, ast: ast);
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok,
            detail: ast == null ? 'lexer' : 'ast', findings: findings.length),
        findings);
  }
}

/// Entropie de Shannon (bits par caractère).
double shannonEntropy(String s) {
  final freq = <int, int>{};
  for (final c in s.codeUnits) {
    freq[c] = (freq[c] ?? 0) + 1;
  }
  var h = 0.0;
  for (final n in freq.values) {
    final p = n / s.length;
    h -= p * math.log(p) / math.ln2;
  }
  return h;
}

final _entropyToken = RegExp(r'[A-Za-z0-9+/=_\-]{24,}');
final _checksumContext = RegExp(
    r'sha\d*sum|md5sum|checksum|sha(?:1|256|512)|integrity|b2sum',
    caseSensitive: false);

/// Jeton ressemblant à un secret aléatoire : mélange majuscules, minuscules
/// et chiffres, pas hexadécimal pur (sommes de contrôle), entropie ≥ 4.
bool looksLikeSecret(String token) {
  if (!RegExp(r'[A-Z]').hasMatch(token) ||
      !RegExp(r'[a-z]').hasMatch(token) ||
      !RegExp(r'[0-9]').hasMatch(token)) {
    return false;
  }
  if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(token)) return false;
  if ('/'.allMatches(token).length > 2) return false; // chemin
  if (RegExp(r'^[A-Za-z]+(?:[_-][A-Za-z]+)+$').hasMatch(token)) return false;
  return shannonEntropy(token) >= 4.0;
}

/// Applique toutes les règles intégrées (fonction pure, testable directement).
List<Finding> runBuiltinRules(ScriptInfo s, CheckConfig config, Lang lang,
    {AstFacts? ast}) {
  final out = <Finding>[];
  final lexed = lexScript(s.lines);
  final th = config.thresholds;
  final contexts = config.contexts;

  bool active(RuleInfo r) =>
      r.contexts.isEmpty || r.contexts.any(contexts.contains);

  void add(String id, int line,
      {String? extra,
      String? snippet,
      List<String> eq = const [],
      Severity? severity}) {
    final r = ruleInfo(id);
    if (!active(r)) return;
    out.add(Finding(
      tool: 'builtin',
      ruleId: r.id,
      category: r.category,
      severity: severity ?? r.severity,
      line: line,
      message:
          extra == null ? r.title.of(lang) : '${r.title.of(lang)} ($extra)',
      snippet: snippet,
      equivalents: eq,
      hint: r.fix.of(lang),
    ));
  }

  // ── Règles ligne à ligne ──────────────────────────────────────────────────
  final applicable = [
    for (final r in lineRules)
      if ((r.when == null || r.when!(s)) && !(ast != null && r.astCovered)) r
  ];
  for (final l in lexed) {
    // Le shebang n'est pas du code.
    if (l.number == 1 && s.shebang != null) continue;
    for (final r in applicable) {
      final text = r.onRaw ? l.raw : (r.onBare ? l.bare : l.code);
      if (text.isEmpty) continue;
      final m = r.pattern.firstMatch(text);
      if (m == null) continue;
      if (r.accept != null && !r.accept!(m, l)) continue;
      add(r.id, l.number,
          snippet: r.hideSnippet ? null : l.raw.trim(), eq: r.equivalents);
    }
    if (l.raw.length > th.maxLineLength && !l.inHeredoc) {
      add('MNT001', l.number,
          extra: '${l.raw.length} > ${th.maxLineLength}', eq: const ['E006']);
    }
    // Secrets par entropie (heredocs compris), hors contexte de somme de
    // contrôle.
    if (!_checksumContext.hasMatch(l.raw) &&
        _entropyToken.allMatches(l.raw).any((m) => looksLikeSecret(m[0]!))) {
      add('SEC022', l.number, eq: const ['SEC002', 'GL*', 'TH*']);
    }
  }

  // ── Structure : fonctions, imbrication, boucles, commandes ───────────────
  final int functions;
  if (ast != null) {
    functions = ast.functions.length;
    _astStructure(ast, s, th, add, lang);
  } else {
    functions = _lexerStructure(lexed, th, add);
  }

  // ── Règles « fichier » ────────────────────────────────────────────────────
  final code = s.codeLines;
  final hasPipes =
      lexed.any((l) => RegExp(r'[^|]\|[^|]').hasMatch(' ${l.bare} '));

  if (s.hasCrlf) add('ROB009', 0, eq: const ['SC1017']);
  if (s.shebang == null) {
    add('POR001', 0, eq: const ['SC2148']);
  } else {
    final interp = s.shebang!.substring(2).trim().split(RegExp(r'\s+')).first;
    if (!RegExp(r'^/(?:usr/)?bin/[\w.-]+$').hasMatch(interp)) {
      add('POR002', 1, extra: interp);
    }
  }
  if (code >= 5) {
    if (!_hasErrexit(s)) add('ROB001', 0);
    if (!_hasSetOption(s, 'u', 'nounset')) add('ROB003', 0);
    if (_bashLike(s) &&
        hasPipes &&
        !RegExp(r'\bpipefail\b').hasMatch(s.content)) {
      add('ROB002', 0);
    }
  }
  if (RegExp(r'\bmktemp\b').hasMatch(s.content) &&
      !RegExp(r'(?:^\s*|[;&]\s*)trap\s', multiLine: true).hasMatch(s.content)) {
    final line = lexed.firstWhere((l) => l.code.contains('mktemp')).number;
    add('ROB004', line);
  }

  // Contextes d'exécution.
  if (!_setsPath(s)) {
    add('SEC017', 0);
    add('ROB016', 0, eq: const ['SEC017']);
  }
  if (!RegExp(
          r'\bflock\b|\blockfile\b|\bmkdir\s+\S*lock|\.lock\b|\.pid\b|pidfile')
      .hasMatch(s.content)) {
    add('ROB014', 0);
  }
  final prompt = RegExp('$_cmd(?:IFS=\\S*\\s+)?read\\b');
  for (final l in lexed) {
    if (!prompt.hasMatch(l.code)) continue;
    final inLoop = RegExp(
            r'\bwhile\b[^;]*\bread\b|\|\s*(?:while\s+)?(?:IFS=\S*\s+)?read\b')
        .hasMatch(l.code);
    if (!inLoop && !l.code.contains('<')) {
      add('ROB015', l.number, snippet: l.raw.trim());
    }
  }

  // En-tête : un commentaire parmi les 3 premières lignes non vides.
  final head = lexed
      .where((l) =>
          !(l.number == 1 && s.shebang != null) && l.raw.trim().isNotEmpty)
      .take(3);
  if (code >= 5 && !head.any((l) => l.raw.trim().startsWith('#'))) {
    add('MNT004', 0, eq: const ['E005']);
  }
  if (code > 30 && s.commentLines * 20 < code) {
    add('MNT005', 0, extra: '${s.commentLines}/$code');
  }
  if (functions == 0 && code > th.maxLinesWithoutFunction) {
    add('MNT008', 0, extra: '$code');
  }
  var tabIndented = 0, spaceIndented = 0;
  for (final l in lexed) {
    if (l.inHeredoc || l.continuesString || l.raw.trim().isEmpty) continue;
    if (l.raw.startsWith('\t')) tabIndented++;
    if (l.raw.startsWith(' ')) spaceIndented++;
  }
  if (tabIndented > 0 && spaceIndented > 0) {
    add('MNT009', 0, extra: 'tab: $tabIndented, spaces: $spaceIndented');
  }

  final pm = RegExp(
      r'\b(apt-get|apt|yum|dnf|zypper|apk|pacman|emerge)\s+(?:-\S+\s+)*(?:install|update|upgrade|add|-S)\b');
  final managers = <String, int>{};
  for (final l in lexed) {
    for (final m in pm.allMatches(l.bare)) {
      managers.putIfAbsent(m.group(1)!, () => l.number);
    }
  }
  if (managers.length == 1) {
    final e = managers.entries.first;
    add('POR006', e.value, extra: e.key);
  }

  return out;
}

typedef _Add = void Function(String id, int line,
    {String? extra, String? snippet, List<String> eq, Severity? severity});

/// Structure par découpage heuristique (sans shfmt). Renvoie le nombre de
/// fonctions trouvées.
int _lexerStructure(List<CodeLine> lexed, Thresholds th, _Add add) {
  final opener = RegExp(
      r'(?:^|[;&|({)]|\bthen\b|\bdo\b|\belse\b|!)\s*(if|for|while|until|case|select)\b');
  final closer = RegExp(r'(?:^|[;&|)\s])(fi|done|esac)(?=$|[\s;&|)<>])');
  final funcStart = RegExp(
      r'^\s*(?:function\s+([A-Za-z_][\w:.-]*)\s*(?:\(\s*\))?|([A-Za-z_][\w:.-]*)\s*\(\s*\))\s*\{?');
  final openBrace = RegExp(r'(?:^|[\s;&|()])\{(?=\s|$)');
  final closeBrace = RegExp(r'(?:^|[\s;&])\}(?=$|[\s;&|)<>])');
  final loopSubst = RegExp(
      r'(?:\$\(|`)\s*(?:basename|dirname|expr|echo\s[^|)]*\|\s*(?:cut|tr|sed|awk))\b');

  final stack = <String>[];
  var reportedDepth = false;
  var functions = 0;
  String? fnName;
  var fnStart = 0, fnDepth = 0;
  var fnOpened = false;

  for (final l in lexed) {
    if (l.inHeredoc || l.bare.trim().isEmpty) continue;
    final b = l.bare;

    final fm = funcStart.firstMatch(b);
    if (fm != null && fnName == null) {
      functions++;
      fnName = fm.group(1) ?? fm.group(2);
      fnStart = l.number;
      fnDepth = 0;
      fnOpened = false;
    }
    if (fnName != null) {
      fnDepth += openBrace.allMatches(b).length;
      if (fnDepth > 0) fnOpened = true;
      fnDepth -= closeBrace.allMatches(b).length;
      if (fnOpened && fnDepth <= 0) {
        _functionLength(fnName, fnStart, l.number, th, add);
        fnName = null;
      }
    }

    final events = <(int, String, bool)>[
      for (final m in opener.allMatches(b)) (m.start, m.group(1)!, true),
      for (final m in closer.allMatches(b)) (m.start, m.group(1)!, false),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    var inLoop = stack.any(_isLoop);
    for (final (_, kw, open) in events) {
      if (open) {
        stack.add(kw);
        if (_isLoop(kw)) inLoop = true;
        if (stack.length > th.maxNesting && !reportedDepth) {
          reportedDepth = true;
          add('MNT003', l.number, extra: '${stack.length} > ${th.maxNesting}');
        }
      } else if (stack.isNotEmpty) {
        stack.removeLast();
      }
    }
    if (stack.length <= th.maxNesting) reportedDepth = false;
    if (inLoop && loopSubst.hasMatch(l.code)) {
      add('PERF004', l.number, snippet: l.raw.trim());
    }
  }
  return functions;
}

void _functionLength(String name, int start, int end, Thresholds th, _Add add) {
  final len = end - start + 1;
  if (len <= th.maxFunctionLines) return;
  add('MNT002', start,
      extra: '$name : $len > ${th.maxFunctionLines}',
      severity: len > 2 * th.maxFunctionLines ? Severity.medium : Severity.low);
}

/// Structure et règles de commande à partir de l'arbre syntaxique de shfmt.
void _astStructure(
    AstFacts ast, ScriptInfo s, Thresholds th, _Add add, Lang lang) {
  for (final f in ast.functions) {
    _functionLength(f.name, f.startLine, f.endLine, th, add);
  }
  // Imbrication : un signalement par bloc franchissant le seuil.
  for (final n in ast.deepNodes(th.maxNesting)) {
    add('MNT003', n.line, extra: '${n.depth} > ${th.maxNesting}');
  }
  final errexit = _hasErrexit(s);
  String snip(int line) =>
      line >= 1 && line <= s.lines.length ? s.lines[line - 1].trim() : '';

  const perfLoop = {'basename', 'dirname', 'expr'};
  const netTools = {'ifconfig', 'netstat', 'route', 'arp', 'iwconfig'};
  const critical = {
    'mkdir',
    'cp',
    'mv',
    'rm',
    'tar',
    'chown',
    'chmod',
    'ln',
    'install',
    'rsync'
  };

  for (final c in ast.commands) {
    final line = c.line;
    switch (c.name) {
      case 'eval' when c.hasExpansion:
        add('SEC003', line, snippet: snip(line));
      case 'set'
          when c.args.any(
                  (a) => a != null && RegExp(r'^-[a-wyzA-Z]*x').hasMatch(a)) ||
              _hasSeq(c.args, '-o', 'xtrace'):
        add('SEC012', line, snippet: snip(line));
      case 'cd' when !errexit && !c.checked:
        add('ROB005', line, snippet: snip(line), eq: const ['SC2164']);
      case 'read'
          when !c.args
              .any((a) => a != null && RegExp(r'^-[a-zA-Z]*r').hasMatch(a)):
        add('ROB007', line, snippet: snip(line), eq: const ['SC2162']);
      case 'which':
        add('POR004', line, snippet: snip(line), eq: const ['SC2230']);
      case 'egrep' || 'fgrep':
        add('POR005', line,
            snippet: snip(line), eq: const ['SC2196', 'SC2197']);
      case 'expr':
        add('PERF003', line, snippet: snip(line), eq: const ['SC2003']);
    }
    if (netTools.contains(c.name)) add('POR007', line, snippet: snip(line));
    if (c.inSubstitution && c.inLoop && perfLoop.contains(c.name)) {
      add('PERF004', line, snippet: snip(line));
    }
    if (!errexit &&
        s.codeLines >= 5 &&
        critical.contains(c.name) &&
        !c.checked &&
        !c.inSubstitution) {
      add('ROB011', line, snippet: snip(line));
    }
  }
}

bool _hasSeq(List<String?> args, String a, String b) {
  for (var i = 0; i + 1 < args.length; i++) {
    if (args[i] == a && args[i + 1] == b) return true;
  }
  return false;
}

bool _isLoop(String kw) =>
    kw == 'for' || kw == 'while' || kw == 'until' || kw == 'select';
