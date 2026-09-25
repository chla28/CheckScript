/// Registre des règles connues, pour les choisir dans l'interface : règles
/// intégrées (catalogue) et codes des outils externes que l'outil classe
/// explicitement, avec un titre court bilingue. Les codes rencontrés lors
/// d'une analyse s'y ajoutent ([RuleEntry.fromFinding]).
///
/// Une règle est désactivée par son identifiant, tout outil confondu
/// (`rules.disabled` de la configuration, en majuscules).
library;

import '../analyzers/analyzer.dart' show ToolLanguage;
import '../analyzers/external_tools.dart' show bashateMap;
import '../analyzers/python_tools.dart' show banditMap, classifyRuff, pylintMap;
import '../analyzers/shellcheck.dart' show classifyShellcheck;
import '../i18n.dart';
import '../model/finding.dart';
import 'catalog.dart';

class RuleEntry {
  /// Identifiant tel que rapporté (`SC2086`, `B602`, `arg-type`, `PYSEC001`).
  final String id;

  /// Outil(s) produisant la règle (`builtin`, `shellcheck`, `shfmt, ruff`…).
  final String tool;
  final ToolLanguage language;
  final Category category;

  /// Sévérité par défaut ; null quand elle dépend du résultat de l'outil.
  final Severity? severity;

  /// Titre dans la langue demandée ('' si inconnu).
  final String title;
  final String? url;

  const RuleEntry({
    required this.id,
    required this.tool,
    required this.language,
    required this.category,
    this.severity,
    this.title = '',
    this.url,
  });

  /// Clé de désactivation (`rules.disabled`).
  String get key => id.toUpperCase();

  Map<String, Object?> toJson() => {
        'id': id,
        'tool': tool,
        'language': language.name,
        'category': category.name,
        if (severity != null) 'severity': severity!.name,
        'title': title,
        if (url != null) 'url': url,
      };

  /// Relit [toJson] ; null si l'entrée est invalide.
  static RuleEntry? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['tool'] is! String) return null;
    return RuleEntry(
      id: j['id'] as String,
      tool: j['tool'] as String,
      language: ToolLanguage.values.firstWhere((l) => l.name == j['language'],
          orElse: () => ToolLanguage.any),
      category: Category.tryParse('${j['category']}') ?? Category.robustness,
      severity: Severity.tryParse('${j['severity']}'),
      title: j['title'] is String ? j['title'] as String : '',
      url: j['url'] as String?,
    );
  }

  /// Règle découverte lors d'une analyse : le message du problème sert de
  /// titre.
  factory RuleEntry.fromFinding(Finding f, {required bool python}) => RuleEntry(
        id: f.ruleId,
        tool: f.tool,
        language: f.tool == 'gitleaks' || f.tool == 'trufflehog'
            ? ToolLanguage.any
            : (python ? ToolLanguage.python : ToolLanguage.shell),
        category: f.category,
        severity: f.severity,
        title: f.message,
        url: f.url,
      );
}

typedef _Ext = (String id, String tool, Tr title);

const _sh = ToolLanguage.shell;
const _py = ToolLanguage.python;

/// Codes externes classés explicitement, avec un titre court.
const List<_Ext> _external = [
  // ── ShellCheck ────────────────────────────────────────────────────────────
  (
    'SC2114',
    'shellcheck',
    Tr('rm récursif d\'un répertoire système',
        'Recursive rm of a system directory')
  ),
  (
    'SC2115',
    'shellcheck',
    Tr('rm "\$var/" sans \${var:?} : risque de rm -rf /',
        'rm "\$var/" without \${var:?}: may become rm -rf /')
  ),
  (
    'SC2156',
    'shellcheck',
    Tr('find -exec sh -c \'{}\' : injection de noms de fichiers',
        'find -exec sh -c \'{}\': file name injection')
  ),
  (
    'SC2059',
    'shellcheck',
    Tr('Variable dans le format de printf',
        'Variable in the printf format string')
  ),
  (
    'SC2029',
    'shellcheck',
    Tr('ssh : expansion côté client', 'ssh: expansion on the client side')
  ),
  (
    'SC2087',
    'shellcheck',
    Tr('Heredoc non quoté envoyé à ssh', 'Unquoted heredoc sent to ssh')
  ),
  (
    'SC2294',
    'shellcheck',
    Tr('eval appliqué à un tableau', 'eval applied to an array')
  ),
  (
    'SC2035',
    'shellcheck',
    Tr('Glob pouvant être pris pour une option (utiliser ./*)',
        'Glob may be taken as an option (use ./*)')
  ),
  (
    'SC2211',
    'shellcheck',
    Tr('Glob utilisé comme nom de commande', 'Glob used as a command name')
  ),
  (
    'SC2216',
    'shellcheck',
    Tr('Données envoyées à une commande qui ne lit pas l\'entrée',
        'Piping to a command that does not read stdin')
  ),
  ('SC2164', 'shellcheck', Tr('cd sans || exit', 'cd without || exit')),
  (
    'SC2094',
    'shellcheck',
    Tr('Lecture et écriture du même fichier dans un pipeline',
        'Reading and writing the same file in a pipeline')
  ),
  (
    'SC2218',
    'shellcheck',
    Tr('Fonction appelée avant sa définition',
        'Function called before it is defined')
  ),
  (
    'SC2086',
    'shellcheck',
    Tr('Variable non quotée (découpage, globbing)',
        'Unquoted variable (word splitting, globbing)')
  ),
  (
    'SC2046',
    'shellcheck',
    Tr('Substitution \$(…) non quotée', 'Unquoted \$(…) substitution')
  ),
  ('SC2068', 'shellcheck', Tr('\$@ non quoté', 'Unquoted \$@')),
  (
    'SC2045',
    'shellcheck',
    Tr('Boucle sur la sortie de ls', 'Looping over ls output')
  ),
  (
    'SC2044',
    'shellcheck',
    Tr('Boucle sur la sortie de find', 'Looping over find output')
  ),
  (
    'SC2064',
    'shellcheck',
    Tr('trap entre guillemets doubles : expansion immédiate',
        'Double-quoted trap: expanded immediately')
  ),
  (
    'SC2069',
    'shellcheck',
    Tr('Ordre des redirections inversé (2>&1 >fichier)',
        'Redirections in the wrong order (2>&1 >file)')
  ),
  (
    'SC2154',
    'shellcheck',
    Tr('Variable utilisée mais jamais affectée',
        'Variable referenced but never assigned')
  ),
  (
    'SC2155',
    'shellcheck',
    Tr('local x=\$(…) masque le code de retour',
        'local x=\$(…) masks the exit status')
  ),
  ('SC2162', 'shellcheck', Tr('read sans -r', 'read without -r')),
  (
    'SC2015',
    'shellcheck',
    Tr('A && B || C n\'est pas un if/else', 'A && B || C is not if/else')
  ),
  (
    'SC2012',
    'shellcheck',
    Tr('Analyse de la sortie de ls', 'Parsing ls output')
  ),
  (
    'SC2034',
    'shellcheck',
    Tr('Variable affectée mais inutilisée', 'Variable assigned but unused')
  ),
  (
    'SC2006',
    'shellcheck',
    Tr('Backticks : préférer \$(…)', 'Backticks: prefer \$(…)')
  ),
  (
    'SC2004',
    'shellcheck',
    Tr('\$ inutile dans une expression arithmétique',
        'Unneeded \$ in arithmetic')
  ),
  ('SC2181', 'shellcheck', Tr('Test indirect de \$?', 'Indirect check of \$?')),
  ('SC2317', 'shellcheck', Tr('Code inatteignable', 'Unreachable code')),
  ('SC2219', 'shellcheck', Tr('let : préférer \$((…))', 'let: prefer \$((…))')),
  (
    'SC1090',
    'shellcheck',
    Tr('Fichier sourcé non résolu', 'Sourced file cannot be followed')
  ),
  (
    'SC1091',
    'shellcheck',
    Tr('Fichier sourcé introuvable', 'Sourced file not found')
  ),
  ('SC2148', 'shellcheck', Tr('Pas de shebang', 'No shebang')),
  (
    'SC3010',
    'shellcheck',
    Tr('[[ ]] non défini en POSIX sh', '[[ ]] undefined in POSIX sh')
  ),
  (
    'SC3011',
    'shellcheck',
    Tr('<<< non défini en POSIX sh', '<<< undefined in POSIX sh')
  ),
  (
    'SC3020',
    'shellcheck',
    Tr('&> non défini en POSIX sh (lance en arrière-plan)',
        '&> undefined in POSIX sh (runs in background)')
  ),
  (
    'SC3030',
    'shellcheck',
    Tr('Tableaux non définis en POSIX sh', 'Arrays undefined in POSIX sh')
  ),
  (
    'SC3054',
    'shellcheck',
    Tr('Indices de tableau non définis en POSIX sh',
        'Array indices undefined in POSIX sh')
  ),
  (
    'SC3006',
    'shellcheck',
    Tr('(( )) non défini en POSIX sh', '(( )) undefined in POSIX sh')
  ),
  (
    'SC3005',
    'shellcheck',
    Tr('for (( )) non défini en POSIX sh', 'for (( )) undefined in POSIX sh')
  ),
  (
    'SC3018',
    'shellcheck',
    Tr('++ / -- non définis en POSIX sh', '++ / -- undefined in POSIX sh')
  ),
  (
    'SC3001',
    'shellcheck',
    Tr('Substitution de processus <( ) non définie en POSIX sh',
        'Process substitution <( ) undefined in POSIX sh')
  ),
  (
    'SC2039',
    'shellcheck',
    Tr('Construction non définie en POSIX sh',
        'Construct undefined in POSIX sh')
  ),
  (
    'SC2112',
    'shellcheck',
    Tr('Mot-clé function : invalide sous dash',
        '"function" keyword: invalid in dash')
  ),
  (
    'SC2113',
    'shellcheck',
    Tr('function … () : invalide sous dash', 'function … (): invalid in dash')
  ),
  (
    'SC2166',
    'shellcheck',
    Tr('-a / -o dans [ ] : mal défini', '-a / -o in [ ]: not well defined')
  ),
  ('SC2196', 'shellcheck', Tr('egrep obsolète', 'egrep is deprecated')),
  ('SC2197', 'shellcheck', Tr('fgrep obsolète', 'fgrep is deprecated')),
  (
    'SC2230',
    'shellcheck',
    Tr('which non standard : command -v', 'which is non-standard: command -v')
  ),
  (
    'SC1071',
    'shellcheck',
    Tr('Shell non pris en charge par ShellCheck',
        'Shell not supported by ShellCheck')
  ),
  ('SC1008', 'shellcheck', Tr('Shebang non reconnu', 'Unrecognised shebang')),
  ('SC2002', 'shellcheck', Tr('cat inutile', 'Useless cat')),
  (
    'SC2126',
    'shellcheck',
    Tr('grep | wc -l : grep -c', 'grep | wc -l: grep -c')
  ),
  (
    'SC2003',
    'shellcheck',
    Tr('expr : préférer \$((…))', 'expr: prefer \$((…))')
  ),
  ('SC2009', 'shellcheck', Tr('ps | grep : pgrep', 'ps | grep: pgrep')),
  ('SC2010', 'shellcheck', Tr('ls | grep : glob', 'ls | grep: use a glob')),
  ('SC2005', 'shellcheck', Tr('echo \$(cmd) inutile', 'Useless echo \$(cmd)')),
  (
    'SC2116',
    'shellcheck',
    Tr('echo inutile dans une substitution', 'Useless echo in a substitution')
  ),
  (
    'SC2001',
    'shellcheck',
    Tr('sed remplaçable par \${var//…}', 'sed replaceable by \${var//…}')
  ),
  (
    'SC2129',
    'shellcheck',
    Tr('Redirections répétées vers le même fichier',
        'Repeated redirections to the same file')
  ),
  (
    'SC2143',
    'shellcheck',
    Tr('[ -n "\$(grep …)" ] : grep -q', '[ -n "\$(grep …)" ]: grep -q')
  ),
  (
    'SC2233',
    'shellcheck',
    Tr('Sous-shell inutile autour d\'une condition',
        'Useless subshell around a condition')
  ),
  (
    'SC2234',
    'shellcheck',
    Tr('Sous-shell inutile autour d\'un test', 'Useless subshell around a test')
  ),
  (
    'SC2235',
    'shellcheck',
    Tr('Sous-shell inutile : utiliser { }', 'Useless subshell: use { }')
  ),
  // ── Autres outils shell ───────────────────────────────────────────────────
  (
    'FORMAT',
    'shfmt, ruff',
    Tr('Formatage différent du style canonique',
        'Formatting differs from the canonical style')
  ),
  (
    'DIALECT',
    'shfmt',
    Tr('Construction hors du dialecte déclaré',
        'Construct outside the declared dialect')
  ),
  (
    'PARSE',
    'shfmt',
    Tr('Script non analysable par shfmt', 'Script cannot be parsed by shfmt')
  ),
  (
    'CB',
    'checkbashisms',
    Tr('Bashisme possible dans un script /bin/sh',
        'Possible bashism in a /bin/sh script')
  ),
  ('E040', 'bashate', Tr('Erreur de syntaxe', 'Syntax error')),
  ('E041', 'bashate', Tr('\$[ ] obsolète', 'Deprecated \$[ ]')),
  ('E042', 'bashate', Tr('local masque les erreurs', 'local hides errors')),
  ('E043', 'bashate', Tr('Code de retour de (( ))', 'Exit status of (( ))')),
  (
    'E044',
    'bashate',
    Tr('Utiliser [[ ]] pour =~, <, >', 'Use [[ ]] for =~, <, >')
  ),
  (
    'E020',
    'bashate',
    Tr('Déclaration de fonction non conforme',
        'Non-conforming function declaration')
  ),
  // ── Ruff ──────────────────────────────────────────────────────────────────
  (
    'invalid-syntax',
    'ruff',
    Tr('Syntaxe invalide (ou absente de la version cible)',
        'Invalid syntax (or not in the target version)')
  ),
  ('F821', 'ruff', Tr('Nom non défini', 'Undefined name')),
  (
    'F811',
    'ruff',
    Tr('Redéfinition d\'un nom inutilisé', 'Redefinition of unused name')
  ),
  ('F401', 'ruff', Tr('Import inutilisé', 'Unused import')),
  ('F841', 'ruff', Tr('Variable locale inutilisée', 'Unused local variable')),
  ('E722', 'ruff', Tr('except nu', 'Bare except')),
  ('E501', 'ruff', Tr('Ligne trop longue', 'Line too long')),
  (
    'W605',
    'ruff',
    Tr('Séquence d\'échappement invalide', 'Invalid escape sequence')
  ),
  (
    'B006',
    'ruff',
    Tr('Argument par défaut mutable', 'Mutable default argument')
  ),
  (
    'B904',
    'ruff',
    Tr('raise sans from dans un except', 'raise without from inside except')
  ),
  (
    'S101',
    'ruff',
    Tr('assert (supprimé par python -O)', 'assert (removed by python -O)')
  ),
  ('S105', 'ruff', Tr('Mot de passe en dur', 'Hard-coded password')),
  (
    'S106',
    'ruff',
    Tr('Mot de passe en dur passé en argument',
        'Hard-coded password passed as argument')
  ),
  (
    'S107',
    'ruff',
    Tr('Mot de passe en dur comme valeur par défaut',
        'Hard-coded password default value')
  ),
  (
    'S108',
    'ruff',
    Tr('Fichier temporaire au nom prévisible', 'Predictable temporary file')
  ),
  ('S110', 'ruff', Tr('try / except / pass', 'try / except / pass')),
  ('S112', 'ruff', Tr('try / except / continue', 'try / except / continue')),
  (
    'S113',
    'ruff',
    Tr('Requête HTTP sans timeout', 'HTTP request without timeout')
  ),
  (
    'S301',
    'ruff',
    Tr('pickle : désérialisation non sûre', 'pickle: unsafe deserialisation')
  ),
  ('S307', 'ruff', Tr('eval', 'eval')),
  (
    'S311',
    'ruff',
    Tr('random pour de la cryptographie', 'random used for cryptography')
  ),
  ('S324', 'ruff', Tr('Hachage faible (md5, sha1)', 'Weak hash (md5, sha1)')),
  (
    'S501',
    'ruff',
    Tr('Vérification TLS désactivée (verify=False)',
        'TLS verification disabled (verify=False)')
  ),
  ('S506', 'ruff', Tr('yaml.load non sûr', 'Unsafe yaml.load')),
  (
    'S602',
    'ruff',
    Tr('subprocess avec shell=True', 'subprocess with shell=True')
  ),
  (
    'S603',
    'ruff',
    Tr('Appel subprocess (entrée non vérifiée)',
        'subprocess call (unchecked input)')
  ),
  (
    'S604',
    'ruff',
    Tr('shell=True sur un appel de fonction', 'shell=True on a function call')
  ),
  (
    'S605',
    'ruff',
    Tr('os.system / lancement par un shell', 'os.system / shell launch')
  ),
  (
    'S607',
    'ruff',
    Tr('Exécutable sans chemin absolu', 'Executable without absolute path')
  ),
  (
    'S608',
    'ruff',
    Tr('Requête SQL construite par concaténation',
        'SQL query built by concatenation')
  ),
  (
    'PLW1510',
    'ruff',
    Tr('subprocess.run sans check', 'subprocess.run without check')
  ),
  ('PLW1514', 'ruff', Tr('open sans encoding', 'open without encoding')),
  (
    'PLR2004',
    'ruff',
    Tr('Constante « magique » dans une comparaison',
        'Magic value in comparison')
  ),
  (
    'SIM115',
    'ruff',
    Tr('open hors d\'un bloc with', 'open outside a with block')
  ),
  (
    'EXE001',
    'ruff',
    Tr('Shebang sur un fichier non exécutable',
        'Shebang on a non-executable file')
  ),
  ('EXE003', 'ruff', Tr('Shebang sans python', 'Shebang without python')),
  (
    'T100',
    'ruff',
    Tr('Point d\'arrêt (breakpoint) oublié', 'Leftover breakpoint')
  ),
  // ── Bandit (sévérité fixée par Bandit) ────────────────────────────────────
  ('B101', 'bandit', Tr('assert', 'assert')),
  ('B105', 'bandit', Tr('Mot de passe en dur', 'Hard-coded password')),
  (
    'B106',
    'bandit',
    Tr('Mot de passe en dur passé en argument',
        'Hard-coded password passed as argument')
  ),
  (
    'B107',
    'bandit',
    Tr('Mot de passe en dur comme valeur par défaut',
        'Hard-coded password default value')
  ),
  (
    'B108',
    'bandit',
    Tr('Fichier temporaire au nom prévisible', 'Predictable temporary file')
  ),
  ('B110', 'bandit', Tr('try / except / pass', 'try / except / pass')),
  ('B112', 'bandit', Tr('try / except / continue', 'try / except / continue')),
  (
    'B113',
    'bandit',
    Tr('Requête HTTP sans timeout', 'HTTP request without timeout')
  ),
  (
    'B301',
    'bandit',
    Tr('pickle : désérialisation non sûre', 'pickle: unsafe deserialisation')
  ),
  ('B307', 'bandit', Tr('eval', 'eval')),
  ('B403', 'bandit', Tr('Import de pickle', 'pickle import')),
  ('B404', 'bandit', Tr('Import de subprocess', 'subprocess import')),
  (
    'B501',
    'bandit',
    Tr('Vérification TLS désactivée', 'TLS verification disabled')
  ),
  ('B506', 'bandit', Tr('yaml.load non sûr', 'Unsafe yaml.load')),
  (
    'B602',
    'bandit',
    Tr('subprocess avec shell=True', 'subprocess with shell=True')
  ),
  (
    'B603',
    'bandit',
    Tr('Appel subprocess sans shell', 'subprocess call without shell')
  ),
  (
    'B605',
    'bandit',
    Tr('Lancement par un shell (os.system…)', 'Shell launch (os.system…)')
  ),
  (
    'B607',
    'bandit',
    Tr('Exécutable sans chemin absolu', 'Executable without absolute path')
  ),
  // ── Pylint ────────────────────────────────────────────────────────────────
  ('W0122', 'pylint', Tr('exec', 'exec')),
  ('W0123', 'pylint', Tr('eval', 'eval')),
  (
    'W1510',
    'pylint',
    Tr('subprocess.run sans check', 'subprocess.run without check')
  ),
  (
    'W0102',
    'pylint',
    Tr('Argument par défaut mutable', 'Mutable default argument')
  ),
  ('W0702', 'pylint', Tr('except nu', 'Bare except')),
  ('W1514', 'pylint', Tr('open sans encoding', 'open without encoding')),
  ('E0602', 'pylint', Tr('Nom non défini', 'Undefined name')),
  ('C0103', 'pylint', Tr('Nom non conforme', 'Invalid name')),
  (
    'C0114',
    'pylint',
    Tr('Docstring de module absente', 'Missing module docstring')
  ),
  // ── Radon, Vermin ─────────────────────────────────────────────────────────
  (
    'CC',
    'radon',
    Tr('Complexité cyclomatique élevée', 'High cyclomatic complexity')
  ),
  (
    'MI',
    'radon',
    Tr('Indice de maintenabilité faible', 'Low maintainability index')
  ),
  (
    'VERMIN',
    'vermin',
    Tr('Construction au-delà de la version de Python cible',
        'Construct beyond the target Python version')
  ),
];

/// Langage, catégorie et sévérité par défaut d'un code externe.
(ToolLanguage, Category, Severity?) _classify(String id, String tool) {
  final sc = RegExp(r'^SC(\d{4})$').firstMatch(id);
  if (sc != null) {
    final (c, s) = classifyShellcheck(int.parse(sc[1]!), 'warning');
    return (_sh, c, s);
  }
  switch (tool) {
    case 'ruff':
      final (c, s) = classifyRuff(id);
      return (_py, c, s);
    case 'bandit':
      final m = banditMap[id];
      return (_py, m?.$1 ?? Category.security, m?.$2);
    case 'pylint':
      final m = pylintMap[id];
      return (_py, m?.$1 ?? Category.maintainability, m?.$2 ?? Severity.low);
    case 'bashate':
      final m = bashateMap[id];
      return (_sh, m?.$1 ?? Category.maintainability, m?.$2 ?? Severity.low);
  }
  return switch (id) {
    'FORMAT' => (ToolLanguage.any, Category.maintainability, Severity.low),
    'DIALECT' || 'CB' => (_sh, Category.portability, Severity.medium),
    'PARSE' => (_sh, Category.robustness, Severity.high),
    'CC' || 'MI' => (_py, Category.maintainability, null),
    'VERMIN' => (_py, Category.portability, Severity.high),
    _ => (ToolLanguage.any, Category.robustness, null),
  };
}

/// Toutes les règles connues : intégrées (shell puis Python), contrôle de
/// syntaxe, puis codes externes classés.
List<RuleEntry> knownRules(Lang lang) => [
      for (final r in allBuiltinRules())
        RuleEntry(
          id: r.id,
          tool: 'builtin',
          language: r.python ? _py : _sh,
          category: r.category,
          severity: r.severity,
          title: r.title.of(lang),
        ),
      RuleEntry(
        id: 'SYNTAX',
        tool: 'syntax',
        language: ToolLanguage.any,
        category: Category.robustness,
        severity: Severity.critical,
        title: lang == Lang.fr
            ? 'Erreur de syntaxe (bash -n, compilation Python)'
            : 'Syntax error (bash -n, Python compilation)',
      ),
      for (final (id, tool, title) in _external)
        () {
          final (language, category, severity) = _classify(id, tool);
          return RuleEntry(
            id: id,
            tool: tool,
            language: language,
            category: category,
            severity: severity,
            title: title.of(lang),
            url: id.startsWith('SC')
                ? 'https://www.shellcheck.net/wiki/$id'
                : null,
          );
        }(),
    ];
