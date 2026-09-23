/// Règles intégrées (Dart) : toujours disponibles, elles couvrent les points
/// que les outils externes ne traitent pas (secrets, téléchargements exécutés,
/// permissions, structure du code…) et assurent une analyse minimale quand
/// aucun outil externe n'est installé.
///
/// Chaque règle déclare ses `equivalents` (codes ShellCheck, bashate…) : si
/// l'outil externe a signalé la même chose sur la même ligne, le doublon est
/// supprimé par le moteur.
library;

import '../config.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../script_info.dart';
import 'analyzer.dart';
import 'shell_lexer.dart';

/// Préfixe « position de commande » : début de ligne ou après un séparateur.
const _cmd =
    r'(?:^\s*|[;&|({]\s*|\$\(\s*|`\s*|\b(?:then|do|else|if|while|until|!)\s+)';

/// Description d'une règle intégrée (utilisée aussi par `--list-rules`).
class RuleInfo {
  final String id;
  final Category category;
  final Severity severity;
  final Tr title;
  const RuleInfo(this.id, this.category, this.severity, this.title);
}

/// Règle appliquée ligne par ligne par expression régulière.
class LineRule {
  final RuleInfo info;
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

  LineRule(String id, Category c, Severity s, Tr title, String re,
      {this.equivalents = const [],
      this.onRaw = false,
      this.when,
      this.accept,
      this.hideSnippet = false,
      bool caseSensitive = true})
      : info = RuleInfo(id, c, s, title),
        pattern = RegExp(re, caseSensitive: caseSensitive);
}

bool _posix(ScriptInfo s) => s.dialect.isPosix;
bool _bashLike(ScriptInfo s) =>
    s.dialect == Dialect.bash ||
    s.dialect == Dialect.ksh ||
    s.dialect == Dialect.zsh;

const _sec = Category.security;
const _rob = Category.robustness;
const _mnt = Category.maintainability;
const _por = Category.portability;
const _perf = Category.performance;
const _c = Severity.critical;
const _h = Severity.high;
const _m = Severity.medium;
const _l = Severity.low;

final List<LineRule> lineRules = [
  // ── Sécurité ──────────────────────────────────────────────────────────────
  LineRule(
      'SEC001',
      _sec,
      _c,
      Tr('Contenu téléchargé exécuté directement par un shell (curl|sh)',
          'Downloaded content piped straight into a shell (curl|sh)'),
      r'\b(?:curl|wget|fetch)\b[^|;&]*\|\s*(?:sudo\s+(?:-\S+\s+)*)?(?:env\s+)?(?:/(?:usr/)?bin/)?(?:ba|da|z|k)?sh\b'
          r'|\b(?:(?:ba|da|z|k)?sh|source|\.)\s+(?:-c\s+)?["\x27]?(?:<\(|\$\()\s*(?:curl|wget)\b'),
  LineRule(
      'SEC002',
      _sec,
      _c,
      Tr('Secret (mot de passe, jeton, clé) écrit en dur dans le script',
          'Hard-coded secret (password, token, key) in the script'),
      r'''(?:^|[\s;])(?:export\s+|local\s+|readonly\s+|declare\s+(?:-\w+\s+)*)?[A-Za-z_]*(?:pass(?:word|wd)?|secret|token|api_?key|access_?key|private_?key|credential)s?(?<!_(?:file|path|dir|url|name|len|length|min|max|prompt|var|env|cmd|type|id))=(['"]?)(?![$`(])[^'"\s]{4,}\1(?:\s|;|$)''',
      caseSensitive: false,
      hideSnippet: true),
  LineRule(
      'SEC002',
      _sec,
      _c,
      Tr('Clé privée ou jeton d\'accès reconnaissable dans le script',
          'Recognisable private key or access token in the script'),
      r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{36}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}',
      onRaw: true,
      hideSnippet: true),
  LineRule(
      'SEC003',
      _sec,
      _h,
      Tr('eval appliqué à une expansion : risque d\'injection de commande',
          'eval applied to an expansion: command injection risk'),
      '${_cmd}eval\\s+.*[\$`]'),
  LineRule(
      'SEC004',
      _sec,
      _h,
      Tr('Permissions en écriture pour tous (chmod 777/666, o+w)',
          'World-writable permissions (chmod 777/666, o+w)'),
      r'\bchmod\s+(?:-\w+\s+)*(?:0*[0-7]?[0-7][0-7][2367]|[ugoa]*[oa][ugoa]*[+=][rwxXst]*w)\b'),
  LineRule(
      'SEC005',
      _sec,
      _h,
      Tr('Vérification TLS / clé d\'hôte désactivée',
          'TLS / host key verification disabled'),
      r'\bcurl\b[^|;]*\s(?:--insecure|-[a-zA-Z]*k[a-zA-Z]*)\b|--no-check-certificate'
          r'|StrictHostKeyChecking[= ]+no\b|UserKnownHostsFile[= ]+/dev/null'
          r'|sslVerify\s*=?\s*false|GIT_SSL_NO_VERIFY=|--trusted-host\b',
      caseSensitive: false),
  LineRule(
      'SEC006',
      _sec,
      _m,
      Tr('Téléchargement en clair (http://) : contenu falsifiable',
          'Clear-text download (http://): content can be tampered with'),
      r'\b(?:curl|wget|git\s+clone)\b[^|;]*\bhttp://(?!localhost\b|127\.|\[::1\])'),
  LineRule(
      'SEC007',
      _sec,
      _h,
      Tr('rm récursif sur un chemin construit avec une variable non protégée (utiliser "\${var:?}")',
          'Recursive rm on a path built from an unguarded variable (use "\${var:?}")'),
      // Variable suivie d'un « / » (rm -rf "$DIR/…" → rm -rf /… si vide) ou
      // variable non quotée.
      r'\brm\s+(?:-\w+\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\b.*(?:\$\{?[A-Za-z_]\w*\}?"?/|\s\$\{?[A-Za-z_]\w*\}?(?=\s|;|$))',
      equivalents: ['SC2115', 'SC2114'],
      accept: (m, l) => !RegExp(r'\$\{[A-Za-z_]\w*:\?').hasMatch(l.code)),
  LineRule(
      'SEC008',
      _sec,
      _c,
      Tr('Suppression récursive de la racine ou d\'un répertoire système',
          'Recursive removal of the root or of a system directory'),
      r'\brm\s+(?:-\w+\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\s+(?:--no-preserve-root\s+)?["\x27]?/(?:\*|(?:bin|boot|etc|home|lib|lib64|opt|root|sbin|srv|usr|var)/?\*?)?["\x27]?(?:\s|;|$)',
      equivalents: ['SC2114', 'SC2115']),
  LineRule(
      'SEC009',
      _sec,
      _m,
      Tr('Fichier temporaire au nom prévisible dans /tmp (utiliser mktemp)',
          'Predictable temporary file name in /tmp (use mktemp)'),
      r'''(?:>>?\s*|\b(?:tee|touch)\s+(?:-\w+\s+)*)["']?/(?:var/)?tmp/[A-Za-z0-9_.${}-]+'''),
  LineRule(
      'SEC010',
      _sec,
      _h,
      Tr('Mot de passe transmis en ligne de commande (visible dans ps)',
          'Password passed on the command line (visible in ps)'),
      r'\becho\b.*\|\s*sudo\s+(?:-\w+\s+)*-S\b|\bsshpass\s+-p|\bmysql(?:dump|admin)?\b.*\s-p[^\s-]|--password[= ]\S',
      hideSnippet: true),
  LineRule(
      'SEC011',
      _sec,
      _m,
      Tr('Chargement (source) d\'un fichier depuis un emplacement non fiable',
          'Sourcing a file from an untrusted location'),
      '$_cmd(?:source|\\.)\\s+["\']?(?:/tmp/|/var/tmp/|https?://)'),
  LineRule(
      'SEC012',
      _sec,
      _l,
      Tr('Trace d\'exécution (set -x) : des secrets peuvent apparaître dans les journaux',
          'Execution trace (set -x): secrets may leak into logs'),
      '${_cmd}set\\s+(?:-[a-wyzA-Z]*x|-o\\s+xtrace)\\b'),
  LineRule(
      'SEC013',
      _sec,
      _h,
      Tr('Positionnement d\'un bit setuid/setgid',
          'Setting a setuid/setgid bit'),
      r'\bchmod\s+(?:-\w+\s+)*(?:[ugoa]*\+[rwxX]*s|0*[2467][0-7]{3})\b'),
  LineRule(
      'SEC014',
      _sec,
      _m,
      Tr('Saisie d\'un secret sans masquage (read sans -s)',
          'Secret prompted without masking (read without -s)'),
      r'\bread\b(?![^;|&]*\s-[a-zA-Z]*s)[^;|&]*\b(?:pass(?:word|wd)?|secret|token|pin)\b',
      caseSensitive: false),

  // ── Robustesse ────────────────────────────────────────────────────────────
  LineRule(
      'ROB005',
      _rob,
      _m,
      Tr('cd sans contrôle d\'échec (ajouter || exit)',
          'cd without failure check (add || exit)'),
      '${_cmd}cd(?:\\s+[^;&|]*)?\\s*\$',
      equivalents: ['SC2164'],
      when: (s) => !_hasErrexit(s)),
  LineRule(
      'ROB006',
      _rob,
      _m,
      Tr('Variable non quotée dans un test [ ] (échoue si vide ou avec espaces)',
          'Unquoted variable in a [ ] test (fails when empty or with spaces)'),
      r'(?:^|\s)\[\s+\$\{?\w+\}?\s+(?:==?|!=|-(?:eq|ne|lt|gt|le|ge))\s',
      equivalents: ['SC2086']),
  LineRule(
      'ROB007',
      _rob,
      _l,
      Tr('read sans -r : les antislashs sont interprétés',
          'read without -r: backslashes are interpreted'),
      '$_cmd(?:IFS=\\S*\\s+)?read\\b(?![^;|&]*\\s-[a-zA-Z]*r)',
      equivalents: ['SC2162']),
  LineRule(
      'ROB008',
      _rob,
      _m,
      Tr('Boucle sur la sortie de ls (casse sur les noms avec espaces)',
          'Looping over ls output (breaks on names with spaces)'),
      r'\bfor\s+\w+\s+in\s+(?:\$\(|`)\s*ls\b',
      equivalents: ['SC2045']),
  LineRule(
      'ROB010',
      _rob,
      _m,
      Tr('\$@ / \$* non quoté : les arguments sont re-découpés',
          'Unquoted \$@ / \$*: arguments are re-split'),
      r'(?<!["\w$\\])\$[@*](?![\w"])',
      equivalents: ['SC2068', 'SC2048']),

  // ── Maintenabilité ────────────────────────────────────────────────────────
  LineRule(
      'MNT006',
      _mnt,
      _l,
      Tr('Marqueur de travail inachevé (TODO/FIXME/XXX/HACK)',
          'Unfinished work marker (TODO/FIXME/XXX/HACK)'),
      r'#.*\b(?:TODO|FIXME|XXX|HACK)\b',
      onRaw: true),
  LineRule(
      'MNT007',
      _mnt,
      _l,
      Tr('Substitution par backticks : préférer \$(…)',
          'Backtick substitution: prefer \$(…)'),
      r'`[^`]+`',
      equivalents: ['SC2006']),
  LineRule('MNT010', _mnt, _l,
      Tr('Espaces en fin de ligne', 'Trailing whitespace'), r'[ \t]+$',
      onRaw: true, equivalents: ['E001']),

  // ── Portabilité ───────────────────────────────────────────────────────────
  LineRule(
      'POR003',
      _por,
      _m,
      Tr('Construction bash dans un script /bin/sh',
          'Bash construct in a /bin/sh script'),
      r'\[\[|(?:^|[;&]\s*)function\s+\w+|\[\s[^\]]*\s==\s|\$'
          r"'"
          r'|\b\w+=\(|'
          '$_cmd'
          r'source\s|<<<|&>|\$\{\w+:-?\d|\$\{\w+//?[^}]|\becho\s+-[neE]+\s|\(\(|\blet\s|\b(?:declare|typeset)\b|\$(?:RANDOM|BASH_\w+|PIPESTATUS)\b|\bselect\s+\w+\s+in\b',
      when: _posix,
      equivalents: ['SC3*', 'SC2039', 'SC2112', 'SC2113', 'CB', 'DIALECT']),
  LineRule(
      'POR004',
      _por,
      _l,
      Tr('which n\'est pas standard : utiliser command -v',
          'which is not standard: use command -v'),
      '${_cmd}which\\s',
      equivalents: ['SC2230']),
  LineRule(
      'POR005',
      _por,
      _l,
      Tr('egrep/fgrep sont obsolètes : utiliser grep -E / grep -F',
          'egrep/fgrep are deprecated: use grep -E / grep -F'),
      '$_cmd[ef]grep\\b',
      equivalents: ['SC2196', 'SC2197']),
  LineRule(
      'POR007',
      _por,
      _l,
      Tr('Outil réseau obsolète (net-tools) : préférer ip / ss',
          'Deprecated networking tool (net-tools): prefer ip / ss'),
      '$_cmd(?:ifconfig|netstat|route|arp|iwconfig)\\b'),

  // ── Performance ───────────────────────────────────────────────────────────
  LineRule(
      'PERF001',
      _perf,
      _l,
      Tr('cat inutile : passer le fichier en argument ou en redirection',
          'Useless cat: pass the file as an argument or redirection'),
      '${_cmd}cat\\s+"?[^\\s|;&<>(-][^\\s|;&<>]*"?\\s*\\|',
      equivalents: ['SC2002']),
  LineRule(
      'PERF002',
      _perf,
      _l,
      Tr('grep | wc -l : utiliser grep -c', 'grep | wc -l: use grep -c'),
      r'\bgrep\b[^|]*\|\s*wc\s+-l\b',
      equivalents: ['SC2126']),
  LineRule(
      'PERF003',
      _perf,
      _l,
      Tr('expr lance un processus : utiliser \$((…))',
          'expr spawns a process: use \$((…))'),
      '${_cmd}expr\\s',
      equivalents: ['SC2003']),
  LineRule(
      'PERF005',
      _perf,
      _l,
      Tr('Enchaînement de filtres réductible à une seule commande (grep|grep, grep|awk, sed|sed)',
          'Filter chain reducible to a single command (grep|grep, grep|awk, sed|sed)'),
      r'\bgrep\b[^|]*\|\s*(?:grep|awk)\b|\bsed\b[^|]*\|\s*sed\b'),
  LineRule(
      'PERF006',
      _perf,
      _l,
      Tr('ps | grep : utiliser pgrep', 'ps | grep: use pgrep'),
      r'\bps\b[^|]*\|\s*grep\b',
      equivalents: ['SC2009']),
  LineRule(
      'PERF007',
      _perf,
      _l,
      Tr('for … in \$(seq …) : préférer une boucle arithmétique',
          'for … in \$(seq …): prefer an arithmetic loop'),
      r'\bfor\s+\w+\s+in\s+(?:\$\(|`)\s*seq\b',
      when: _bashLike),
  LineRule(
      'PERF008',
      _perf,
      _l,
      Tr('echo inutile dans une substitution',
          'Useless echo in a substitution'),
      r'''\$\(\s*echo\s+["']?\$\{?\w+\}?["']?\s*\)''',
      equivalents: ['SC2116']),
  LineRule(
      'PERF009',
      _perf,
      _l,
      Tr('\$(cat fichier) : utiliser \$(< fichier) en bash',
          '\$(cat file): use \$(< file) in bash'),
      r'\$\(\s*cat\s+[^|;&)]+\)',
      when: _bashLike),
];

/// Règles « fichier » ou structurelles (non exprimables ligne à ligne).
final List<RuleInfo> structuralRules = [
  RuleInfo(
      'ROB001',
      _rob,
      _m,
      Tr('Pas d\'arrêt sur erreur (set -e / set -o errexit)',
          'No exit on error (set -e / set -o errexit)')),
  RuleInfo(
      'ROB002',
      _rob,
      _l,
      Tr('Pipelines sans set -o pipefail : les échecs intermédiaires sont ignorés',
          'Pipelines without set -o pipefail: intermediate failures are ignored')),
  RuleInfo(
      'ROB003',
      _rob,
      _l,
      Tr('Variables non définies non détectées (set -u / set -o nounset)',
          'Undefined variables not detected (set -u / set -o nounset)')),
  RuleInfo(
      'ROB004',
      _rob,
      _l,
      Tr('Fichier temporaire (mktemp) sans nettoyage par trap',
          'Temporary file (mktemp) without trap cleanup')),
  RuleInfo(
      'ROB009',
      _rob,
      _h,
      Tr('Fins de ligne Windows (CRLF) : le script ne s\'exécutera pas correctement',
          'Windows line endings (CRLF): the script will not run correctly')),
  RuleInfo('MNT001', _mnt, _l, Tr('Ligne trop longue', 'Line too long')),
  RuleInfo('MNT002', _mnt, _l, Tr('Fonction trop longue', 'Function too long')),
  RuleInfo(
      'MNT003', _mnt, _m, Tr('Imbrication trop profonde', 'Nesting too deep')),
  RuleInfo(
      'MNT004',
      _mnt,
      _l,
      Tr('Pas de commentaire d\'en-tête décrivant le script',
          'No header comment describing the script')),
  RuleInfo(
      'MNT005', _mnt, _l, Tr('Code très peu commenté', 'Very few comments')),
  RuleInfo(
      'MNT008',
      _mnt,
      _m,
      Tr('Script long sans aucune fonction',
          'Long script without any function')),
  RuleInfo(
      'MNT009',
      _mnt,
      _l,
      Tr('Indentation mélangeant tabulations et espaces',
          'Indentation mixes tabs and spaces')),
  RuleInfo(
      'POR001',
      _por,
      _m,
      Tr('Pas de shebang : interpréteur indéterminé',
          'No shebang: interpreter is undefined')),
  RuleInfo(
      'POR002',
      _por,
      _l,
      Tr('Chemin d\'interpréteur non standard dans le shebang',
          'Non-standard interpreter path in the shebang')),
  RuleInfo(
      'POR006',
      _por,
      _l,
      Tr('Gestionnaire de paquets propre à une distribution, sans alternative',
          'Distribution-specific package manager, without alternative')),
  RuleInfo(
      'PERF004',
      _perf,
      _l,
      Tr('Commande externe lancée à chaque tour de boucle (préférer une expansion de paramètre)',
          'External command spawned on every loop iteration (prefer parameter expansion)')),
];

/// Toutes les règles intégrées, triées par identifiant (`--list-rules`).
List<RuleInfo> allBuiltinRules() {
  final seen = <String>{};
  final all = [
    for (final r in lineRules)
      if (seen.add(r.info.id)) r.info,
    for (final r in structuralRules)
      if (seen.add(r.id)) r,
  ];
  int order(String id) =>
      ['SEC', 'ROB', 'MNT', 'POR', 'PERF'].indexWhere(id.startsWith);
  all.sort((a, b) {
    final o = order(a.id).compareTo(order(b.id));
    return o != 0 ? o : a.id.compareTo(b.id);
  });
  return all;
}

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
    final findings = runBuiltinRules(ctx.script, ctx.config, ctx.lang);
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok, findings: findings.length), findings);
  }
}

/// Applique toutes les règles intégrées (fonction pure, testable directement).
List<Finding> runBuiltinRules(ScriptInfo s, CheckConfig config, Lang lang) {
  final out = <Finding>[];
  final lexed = lexScript(s.lines);
  final th = config.thresholds;

  Finding mk(RuleInfo r, int line,
          {String? extra, String? snippet, List<String> eq = const []}) =>
      Finding(
        tool: 'builtin',
        ruleId: r.id,
        category: r.category,
        severity: r.severity,
        line: line,
        message:
            extra == null ? r.title.of(lang) : '${r.title.of(lang)} ($extra)',
        snippet: snippet,
        equivalents: eq,
      );
  RuleInfo rule(String id) => structuralRules.firstWhere((r) => r.id == id);

  // ── Règles ligne à ligne ──────────────────────────────────────────────────
  final applicable = [
    for (final r in lineRules)
      if (r.when == null || r.when!(s)) r
  ];
  for (final l in lexed) {
    // Le shebang n'est pas du code.
    if (l.number == 1 && s.shebang != null) continue;
    for (final r in applicable) {
      final text = r.onRaw ? l.raw : l.code;
      if (text.isEmpty) continue;
      final m = r.pattern.firstMatch(text);
      if (m == null) continue;
      if (r.accept != null && !r.accept!(m, l)) continue;
      out.add(mk(r.info, l.number,
          snippet: r.hideSnippet ? null : l.raw.trim(), eq: r.equivalents));
    }
    if (l.raw.length > th.maxLineLength && !l.inHeredoc) {
      out.add(mk(rule('MNT001'), l.number,
          extra: '${l.raw.length} > ${th.maxLineLength}', eq: const ['E006']));
    }
  }

  // ── Structure : imbrication, boucles, fonctions ───────────────────────────
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
  // Fonction en cours : (nom, ligne de début, profondeur d'accolades).
  String? fnName;
  var fnStart = 0, fnDepth = 0;
  var fnOpened = false;

  for (final l in lexed) {
    if (l.inHeredoc || l.bare.trim().isEmpty) continue;
    final b = l.bare;

    // Fonctions
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
        final len = l.number - fnStart + 1;
        if (len > th.maxFunctionLines) {
          final r = rule('MNT002');
          out.add(Finding(
            tool: 'builtin',
            ruleId: r.id,
            category: r.category,
            severity:
                len > 2 * th.maxFunctionLines ? Severity.medium : Severity.low,
            line: fnStart,
            message:
                '${r.title.of(lang)} ($fnName : $len > ${th.maxFunctionLines})',
          ));
        }
        fnName = null;
      }
    }

    // Imbrication et boucles : événements triés par position.
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
          out.add(mk(rule('MNT003'), l.number,
              extra: '${stack.length} > ${th.maxNesting}'));
        }
      } else if (stack.isNotEmpty) {
        stack.removeLast();
      }
    }
    if (stack.length <= th.maxNesting) reportedDepth = false;
    if (inLoop && loopSubst.hasMatch(l.code)) {
      out.add(mk(rule('PERF004'), l.number, snippet: l.raw.trim()));
    }
  }

  // ── Règles « fichier » ────────────────────────────────────────────────────
  final code = s.codeLines;
  final hasPipes =
      lexed.any((l) => RegExp(r'[^|]\|[^|]').hasMatch(' ${l.bare} '));

  if (s.hasCrlf) out.add(mk(rule('ROB009'), 0, eq: const ['SC1017']));
  if (s.shebang == null) {
    out.add(mk(rule('POR001'), 0, eq: const ['SC2148']));
  } else {
    final interp = s.shebang!.substring(2).trim().split(RegExp(r'\s+')).first;
    if (!RegExp(r'^/(?:usr/)?bin/[\w.-]+$').hasMatch(interp)) {
      out.add(mk(rule('POR002'), 1, extra: interp));
    }
  }
  if (code >= 5) {
    if (!_hasErrexit(s)) out.add(mk(rule('ROB001'), 0));
    if (!_hasSetOption(s, 'u', 'nounset')) {
      out.add(mk(rule('ROB003'), 0));
    }
    if (_bashLike(s) &&
        hasPipes &&
        !RegExp(r'\bpipefail\b').hasMatch(s.content)) {
      out.add(mk(rule('ROB002'), 0));
    }
  }
  if (RegExp(r'\bmktemp\b').hasMatch(s.content) &&
      !RegExp(r'(?:^\s*|[;&]\s*)trap\s', multiLine: true).hasMatch(s.content)) {
    final line = lexed.firstWhere((l) => l.code.contains('mktemp')).number;
    out.add(mk(rule('ROB004'), line));
  }

  // En-tête : un commentaire parmi les 3 premières lignes non vides.
  final head = lexed
      .where((l) =>
          !(l.number == 1 && s.shebang != null) && l.raw.trim().isNotEmpty)
      .take(3);
  if (code >= 5 && !head.any((l) => l.raw.trim().startsWith('#'))) {
    out.add(mk(rule('MNT004'), 0, eq: const ['E005']));
  }
  if (code > 30 && s.commentLines * 20 < code) {
    out.add(mk(rule('MNT005'), 0, extra: '${s.commentLines}/$code'));
  }
  if (functions == 0 && code > th.maxLinesWithoutFunction) {
    out.add(mk(rule('MNT008'), 0, extra: '$code'));
  }
  var tabIndented = 0, spaceIndented = 0;
  for (final l in lexed) {
    if (l.inHeredoc || l.continuesString || l.raw.trim().isEmpty) continue;
    if (l.raw.startsWith('\t')) tabIndented++;
    if (l.raw.startsWith(' ')) spaceIndented++;
  }
  if (tabIndented > 0 && spaceIndented > 0) {
    out.add(mk(rule('MNT009'), 0,
        extra: 'tab: $tabIndented, spaces: $spaceIndented'));
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
    out.add(mk(rule('POR006'), e.value, extra: e.key));
  }

  return out;
}

bool _isLoop(String kw) =>
    kw == 'for' || kw == 'while' || kw == 'until' || kw == 'select';
