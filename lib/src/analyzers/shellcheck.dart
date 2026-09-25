/// Intégration de ShellCheck (`shellcheck -f json1`).
library;

import 'dart:convert';

import '../config.dart';
import '../model/finding.dart';
import 'analyzer.dart';
import '../json_num.dart';

/// Classement d'un code ShellCheck. Sévérité null : déduite du niveau
/// ShellCheck (error → High, warning → Medium, info/style → Low).
typedef ScMapping = (Category, Severity?);

/// Table de classement des codes ShellCheck les plus significatifs.
/// Les codes absents sont classés par [classifyShellcheck] selon leur plage et
/// leur niveau.
const Map<int, ScMapping> shellcheckMap = {
  // ── Sécurité ──────────────────────────────────────────────────────────────
  2114: (Category.security, Severity.critical), // rm d'un répertoire système
  2115: (Category.security, Severity.critical), // rm "$var/" sans ${var:?}
  2156: (Category.security, Severity.high), // find -exec sh -c '{}' : injection
  2059: (Category.security, Severity.medium), // variable dans le format printf
  2029: (Category.security, Severity.medium), // ssh : expansion côté client
  2087: (Category.security, Severity.medium), // heredoc non quoté vers ssh
  2294: (Category.security, Severity.medium), // eval sur un tableau
  2035: (Category.security, Severity.medium), // glob pouvant devenir une option
  2211: (Category.security, Severity.medium), // glob utilisé comme commande
  2216: (Category.security, Severity.low),
  // ── Robustesse ───────────────────────────────────────────────────────────
  2164: (Category.robustness, Severity.high), // cd sans || exit
  2094: (Category.robustness, Severity.high), // lire et écrire le même fichier
  2218: (
    Category.robustness,
    Severity.high
  ), // fonction appelée avant définition
  2086: (Category.robustness, Severity.medium), // variable non quotée
  2046: (Category.robustness, Severity.medium), // $() non quoté
  2068: (Category.robustness, Severity.medium), // $@ non quoté
  2045: (Category.robustness, Severity.medium), // for f in $(ls)
  2044: (Category.robustness, Severity.medium), // for f in $(find)
  2064: (Category.robustness, Severity.medium), // trap avec guillemets doubles
  2069: (Category.robustness, Severity.medium), // ordre des redirections
  2154: (Category.robustness, Severity.medium), // variable jamais affectée
  2155: (Category.robustness, Severity.low), // local x=$(…) masque le code
  2162: (Category.robustness, Severity.low), // read sans -r
  2015: (Category.robustness, Severity.low), // A && B || C
  2012: (Category.robustness, Severity.low), // ls | …
  // ── Maintenabilité ───────────────────────────────────────────────────────
  2034: (Category.maintainability, Severity.low), // variable inutilisée
  2006: (Category.maintainability, Severity.low), // backticks
  2004: (Category.maintainability, Severity.low), // $ inutile en arithmétique
  2181: (Category.maintainability, Severity.low), // test de $? indirect
  2317: (Category.maintainability, Severity.low), // code inatteignable
  2219: (Category.maintainability, Severity.low), // let
  1090: (Category.maintainability, Severity.low), // source non résolu
  // ── Portabilité ──────────────────────────────────────────────────────────
  2148: (Category.portability, Severity.medium), // pas de shebang
  // Bashismes qui cassent réellement sous dash (/bin/sh de Debian/Ubuntu) :
  // erreur de syntaxe, « not found » ou comportement silencieusement différent.
  3010: (Category.portability, Severity.high), // [[ ]]
  3011: (Category.portability, Severity.high), // <<<
  3020: (Category.portability, Severity.high), // &> (arrière-plan en sh !)
  3030: (Category.portability, Severity.high), // tableaux
  3054: (Category.portability, Severity.high), // tableaux
  3006: (Category.portability, Severity.high), // (( ))
  3005: (Category.portability, Severity.high), // for (( ))
  3018: (Category.portability, Severity.high), // ++ / --
  3001: (Category.portability, Severity.high), // <( ) substitution de processus
  2039: (Category.portability, Severity.medium), // non défini en POSIX sh
  2112: (
    Category.portability,
    Severity.high
  ), // function : syntaxe invalide en dash
  2113: (Category.portability, Severity.high),
  2166: (Category.portability, Severity.low), // -a / -o dans [ ]
  2196: (Category.portability, Severity.low), // egrep obsolète
  2197: (Category.portability, Severity.low), // fgrep obsolète
  2230: (Category.portability, Severity.low), // which non standard
  1071: (Category.portability, Severity.medium), // shell non supporté
  1008: (Category.portability, Severity.medium), // shebang non reconnu
  // ── Performance ──────────────────────────────────────────────────────────
  2002: (Category.performance, Severity.low), // cat inutile
  2126: (Category.performance, Severity.low), // grep | wc -l
  2003: (Category.performance, Severity.low), // expr
  2009: (Category.performance, Severity.low), // ps | grep
  2010: (Category.performance, Severity.low), // ls | grep
  2005: (Category.performance, Severity.low), // echo $(cmd) inutile
  2116: (Category.performance, Severity.low), // echo inutile
  2001: (Category.performance, Severity.low), // sed au lieu de ${//}
  2129: (Category.performance, Severity.low), // redirections répétées
  2143: (Category.performance, Severity.low), // grep -q
  2233: (Category.performance, Severity.low), // sous-shell inutile
  2234: (Category.performance, Severity.low),
  2235: (Category.performance, Severity.low),
};

/// Classe un code ShellCheck selon la table, puis par plage et niveau.
(Category, Severity) classifyShellcheck(int code, String level) {
  final lv = switch (level) {
    'error' => Severity.high,
    'warning' => Severity.medium,
    _ => Severity.low,
  };
  final m = shellcheckMap[code];
  if (m != null) return (m.$1, m.$2 ?? lv);
  // SC3xxx : « In POSIX sh, … is undefined ».
  if (code >= 3000 && code < 4000) {
    return (
      Category.portability,
      level == 'error' || level == 'warning' ? Severity.medium : Severity.low
    );
  }
  // SC1xxx de niveau error : erreur d'analyse syntaxique.
  if (code < 2000 && level == 'error') {
    return (Category.robustness, Severity.high);
  }
  if (level == 'style') return (Category.maintainability, Severity.low);
  return (Category.robustness, lv);
}

class ShellcheckAnalyzer extends Analyzer {
  /// Vérifications optionnelles activées (`shellcheck --list-optional`).
  static const optionalChecks = [
    'add-default-case',
    'avoid-nullary-conditions',
    'check-set-e-suppressed',
    'check-unassigned-uppercase',
    'deprecate-which',
    'useless-use-of-cat',
  ];

  @override
  String get name => 'shellcheck';

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    if (r == null) return null;
    final m = RegExp(r'version:\s*(\S+)').firstMatch(r.stdout);
    return m?.group(1) ?? extractVersion(r.stdout) ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final args = [
      '--format=json1',
      '--enable=${optionalChecks.join(',')}',
      if (ctx.config.excludedFor(name) case final ex when ex.isNotEmpty)
        '--exclude=${ex.join(',')}',
      // Fichiers sourcés suivis, résolus depuis le dossier du script.
      if (ctx.config.followSource) ...[
        '--external-sources',
        '--source-path=SCRIPTDIR'
      ],
      if (ctx.script.dialect.shellcheckName != null)
        '--shell=${ctx.script.dialect.shellcheckName}',
      ctx.filePath,
    ];
    final r = await ctx.run(tc.executable, args);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    // 0 : rien à signaler ; 1 : problèmes trouvés ; autre : erreur d'usage.
    if (r.exitCode > 1 && r.stdout.trim().isEmpty) {
      return AnalyzerResult(
          ToolRun(name, ToolStatus.failed, detail: r.stderr.trim()));
    }
    try {
      final findings = parseShellcheckJson(r.stdout);
      return AnalyzerResult(
          ToolRun(name, ToolStatus.ok, findings: findings.length), findings);
    } on FormatException catch (e) {
      return AnalyzerResult(
          ToolRun(name, ToolStatus.failed, detail: e.message));
    }
  }
}

/// Convertit la sortie `-f json1` de ShellCheck en [Finding]s.
List<Finding> parseShellcheckJson(String json) {
  if (json.trim().isEmpty) return const [];
  final Object? doc;
  try {
    doc = jsonDecode(json);
  } on FormatException {
    throw const FormatException('sortie JSON ShellCheck invalide');
  }
  final comments = doc is Map ? doc['comments'] : doc;
  if (comments is! List) {
    throw const FormatException('sortie JSON ShellCheck inattendue');
  }
  return [
    for (final c in comments.whereType<Map>())
      () {
        final code = jsonInt(c['code'])!;
        final level = '${c['level']}';
        final (cat, sev) = classifyShellcheck(code, level);
        return Finding(
          tool: 'shellcheck',
          ruleId: 'SC$code',
          category: cat,
          severity: sev,
          line: jsonInt(c['line']) ?? 0,
          column: jsonInt(c['column']) ?? 0,
          message: '${c['message']}',
          edits: [
            if (c['fix'] case {'replacements': final List rs})
              for (final r in rs.whereType<Map<String, Object?>>())
                TextEdit.fromJson(r, 'SC$code'),
          ],
        );
      }(),
  ];
}
