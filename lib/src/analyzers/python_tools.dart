/// Intégration des outils d'analyse Python : Ruff (lint et formatage),
/// Bandit, Semgrep, mypy, Pyright, Pylint, Radon et Vermin.
///
/// Chaque outil est classé sur les cinq axes ; les codes qui désignent le même
/// défaut d'un outil à l'autre sont déclarés en `equivalents` (Ruff `S602` =
/// Bandit `B602`, Ruff `PLW0602` = Pylint `W0602`…) pour que le moteur ne
/// garde qu'un problème par ligne.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../json_num.dart';
import '../model/finding.dart';
import 'analyzer.dart';
import '../rules/same_rules.dart' show ruffToPylint;
import 'external_tools.dart' show parseShfmtDiff, pythonSyntaxEquivalents;

const _sec = Category.security;
const _rob = Category.robustness;
const _mnt = Category.maintainability;
const _por = Category.portability;
const _perf = Category.performance;
const _c = Severity.critical;
const _h = Severity.high;
const _m = Severity.medium;
const _l = Severity.low;

/// Configuration Ruff du projet de [scriptPath] : `ruff.toml`,
/// `.ruff.toml` ou `pyproject.toml` avec une section `[tool.ruff`, dans le
/// dossier du script puis ses parents, jusqu'à la racine du dépôt git.
String? ruffProjectConfig(String scriptPath) {
  var dir = File(scriptPath).absolute.parent;
  while (true) {
    for (final name in ['ruff.toml', '.ruff.toml']) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) return f.path;
    }
    final py = File('${dir.path}/pyproject.toml');
    if (py.existsSync() && py.readAsStringSync().contains('[tool.ruff')) {
      return py.path;
    }
    if (FileSystemEntity.typeSync('${dir.path}/.git') !=
        FileSystemEntityType.notFound) {
      return null;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Version cible au format Ruff (`3.9` → `py39`).
String pythonTag(String target) => 'py${target.replaceAll('.', '')}';

/// Vrai si la version cible (`3.9`) est au moins 3.[minor].
bool pythonTargetAtLeast(String target, int minor) {
  final parts = target.split('.');
  return parts.length == 2 && (int.tryParse(parts[1]) ?? 0) >= minor;
}

/// Décode un document JSON éventuellement précédé de journaux (Pyright
/// installé par pip annonce parfois le téléchargement de Node.js).
Object? _decode(String out) {
  final t = out.trim();
  if (t.isEmpty) return null;
  try {
    return jsonDecode(t);
  } on FormatException {
    final i = t.indexOf(RegExp(r'^[\[{]', multiLine: true));
    if (i <= 0) rethrow;
    return jsonDecode(t.substring(i));
  }
}

/// Descend l'échelle de sévérité d'un cran (confiance faible).
Severity _lower(Severity s) =>
    s == Severity.low ? s : Severity.values[s.index + 1];

/// Codes des secrets détectés par les autres outils (dédoublonnage).
const _secretEquivalents = [
  'PYSEC001',
  'GL*',
  'TH*',
  'B105',
  'B106',
  'B107',
  'S105',
  'S106',
  'S107',
];

abstract class PythonAnalyzer extends Analyzer {
  @override
  ToolLanguage get language => ToolLanguage.python;

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    return r == null ? null : extractVersion('${r.stdout}${r.stderr}') ?? '?';
  }

  AnalyzerResult missing() => AnalyzerResult(ToolRun(name, ToolStatus.missing));

  AnalyzerResult failed(String detail) =>
      AnalyzerResult(ToolRun(name, ToolStatus.failed, detail: detail));

  AnalyzerResult ok(List<Finding> findings, {String? detail}) => AnalyzerResult(
      ToolRun(name, ToolStatus.ok, detail: detail, findings: findings.length),
      findings);
}

// ─────────────────────────────────────────────────────────────────────────────
// Ruff : lint (règles choisies) et écart de formatage
// ─────────────────────────────────────────────────────────────────────────────

/// Familles Ruff retenues : erreurs, bugs probables, sécurité, modernisation
/// compatible avec la version cible, performance, simplifications. Les
/// familles de pur style (docstrings, annotations, nommage) sont écartées.
const ruffSelect = [
  'E4', 'E7', 'E9', 'E501', 'W', 'F', 'B', 'S', 'UP', 'PERF', 'C4', 'SIM', //
  'BLE', 'PLE', 'PLW', 'PLR', 'PIE', 'RUF', 'EXE', 'T10', 'ISC', 'A', 'ASYNC',
];

/// Classement des codes Ruff notables ; les autres le sont par famille.
const Map<String, (Category, Severity)> ruffMap = {
  'invalid-syntax': (_rob, _c),
  'F821': (_rob, _h), // nom non défini
  'F811': (_rob, _m), // redéfinition
  'F401': (_mnt, _l), // import inutilisé
  'F841': (_mnt, _l), // variable inutilisée
  'E722': (_rob, _m), // except nu
  'W605': (_rob, _m), // séquence d'échappement invalide
  'B006': (_rob, _m), // argument par défaut mutable
  'B904': (_rob, _l), // raise sans from dans un except
  'S101': (_rob, _l), // assert (supprimé par -O)
  'S105': (_sec, _h), // mot de passe en dur
  'S106': (_sec, _h),
  'S107': (_sec, _h),
  'S108': (_sec, _m), // fichier temporaire prévisible
  'S110': (_rob, _l), // try/except/pass
  'S112': (_rob, _l), // try/except/continue
  'S113': (_rob, _m), // requête HTTP sans timeout
  'S102': (_sec, _h), // exec
  'S301': (_sec, _h), // pickle
  'S307': (_sec, _h), // eval
  'S311': (_sec, _l), // random pour de la cryptographie
  'S324': (_sec, _m), // hachage faible
  'S501': (_sec, _h), // verify=False
  'S506': (_sec, _h), // yaml.load non sûr
  'S602': (_sec, _h), // subprocess shell=True
  'S604': (_sec, _h), // shell=True sur un autre appel
  'S605': (_sec, _h), // os.system
  'S603': (_sec, _l),
  'S607': (_sec, _l), // exécutable sans chemin absolu
  'S608': (_sec, _h), // injection SQL
  'PLW1510': (_rob, _m), // subprocess.run sans check
  'PLW1514': (_por, _l), // open sans encoding
  'SIM115': (_rob, _l), // open hors d'un with
  'EXE003': (_por, _m), // shebang sans python
  'T100': (_rob, _m), // point d'arrêt oublié
};

/// Classement par famille, du préfixe le plus long au plus court.
const List<(String, Category, Severity)> _ruffFamilies = [
  ('E9', _rob, _h),
  ('E7', _rob, _l),
  ('E4', _mnt, _l),
  ('E5', _mnt, _l),
  ('PLE', _rob, _h),
  ('PLW', _rob, _l),
  ('PLR', _mnt, _l),
  ('PERF', _perf, _l),
  ('ASYNC', _perf, _l),
  ('BLE', _rob, _l),
  ('EXE', _por, _l),
  ('T10', _rob, _m),
  ('SIM', _mnt, _l),
  ('PIE', _mnt, _l),
  ('RUF', _mnt, _l),
  ('ISC', _mnt, _l),
  ('UP', _mnt, _l),
  ('C4', _perf, _l),
  ('W', _mnt, _l),
  ('F', _rob, _m),
  ('B', _rob, _l),
  ('S', _sec, _m),
  ('A', _mnt, _l),
];

(Category, Severity) classifyRuff(String code) {
  final m = ruffMap[code];
  if (m != null) return m;
  for (final (prefix, c, s) in _ruffFamilies) {
    if (code.startsWith(prefix)) return (c, s);
  }
  return (_mnt, _l);
}

/// Équivalents d'un code Ruff : Bandit (même numéro que `S`), Pylint,
/// Radon, secrets, syntaxe.
List<String> ruffEquivalents(String code) {
  final out = <String>[];
  final s = RegExp(r'^S(\d{3})$').firstMatch(code);
  if (s != null) out.add('B${s[1]}');
  final pl = RegExp(r'^PL([CERW]\d{4})$').firstMatch(code);
  if (pl != null) out.add(pl[1]!);
  final p = ruffToPylint[code];
  if (p != null) out.add(p);
  if (code == 'C901' || code == 'PLR0912') out.add('CC');
  if (const {'S105', 'S106', 'S107'}.contains(code)) {
    out.addAll(_secretEquivalents);
  }
  if (code == 'invalid-syntax') {
    out.addAll(['SYNTAX', ...pythonSyntaxEquivalents]);
  }
  return out;
}

class RuffAnalyzer extends PythonAnalyzer {
  @override
  String get name => 'ruff';

  /// Options communes à l'analyse, à la correction et au formatage.
  ///
  /// `tools.ruff.config` : absent, réglages de check-script (`--isolated`) ;
  /// `project`, configuration Ruff du projet du script
  /// ([ruffProjectConfig]), sinon réglages de check-script ; autre valeur,
  /// ce fichier de configuration. Avec une configuration Ruff, c'est elle
  /// qui choisit règles, version cible et longueur de ligne.
  static List<String> commonArgs(CheckConfig c, {String? scriptPath}) {
    final file = ruffConfigFile(c, scriptPath);
    return file != null
        ? ['--config', file, '--no-cache']
        : [
            '--isolated',
            '--no-cache',
            '--target-version=${pythonTag(c.pythonTarget)}',
            '--line-length=${c.thresholds.maxLineLength}',
          ];
  }

  /// Fichier de configuration Ruff à utiliser pour [scriptPath], ou null
  /// (réglages de check-script).
  static String? ruffConfigFile(CheckConfig c, String? scriptPath) {
    final v = c.tool('ruff').config;
    if (v == null) return null;
    if (v != 'project') return v;
    return scriptPath == null ? null : ruffProjectConfig(scriptPath);
  }

  /// Options de `ruff check` (règles retenues moins les exclusions, sauf
  /// avec une configuration Ruff).
  static List<String> checkArgs(CheckConfig c, {String? scriptPath}) {
    final tc = c.tool('ruff');
    final own = ruffConfigFile(c, scriptPath) == null;
    return [
      'check',
      ...commonArgs(c, scriptPath: scriptPath),
      if (own) '--select=${ruffSelect.join(',')}',
      if (own && tc.exclude.isNotEmpty) '--ignore=${tc.exclude.join(',')}',
    ];
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final exe = ctx.config.tool(name).executable;
    final r = await ctx.run(exe, [
      ...checkArgs(ctx.config, scriptPath: ctx.script.path),
      '--output-format=json',
      ctx.filePath
    ]);
    if (r == null) return missing();
    if (r.exitCode > 1 && r.stdout.trim().isEmpty) {
      return failed(r.stderr.trim());
    }
    final List<Finding> findings;
    try {
      findings = parseRuff(r.stdout);
    } on FormatException catch (e) {
      return failed(e.message);
    }
    // Écart de formatage (ignoré si le fichier n'est pas analysable).
    final f = await ctx.run(exe, [
      'format',
      ...commonArgs(ctx.config, scriptPath: ctx.script.path),
      '--diff',
      ctx.filePath,
    ]);
    if (f != null && f.exitCode <= 1) {
      findings.addAll(parseShfmtDiff(f.stdout, tool: name));
    }
    return ok(findings);
  }
}

/// Sortie `ruff check --output-format=json`. Seules les corrections
/// qualifiées de sûres (`applicability: safe`) sont retenues.
List<Finding> parseRuff(String json) {
  final doc = _decode(json);
  if (doc == null) return [];
  if (doc is! List) throw const FormatException('sortie JSON Ruff inattendue');
  return [
    for (final d in doc.whereType<Map<String, Object?>>())
      () {
        final code = '${d['code'] ?? 'invalid-syntax'}';
        var (cat, sev) = classifyRuff(code);
        // Syntaxe valide, mais pas dans la version cible (« match statement
        // on Python 3.9 ») : défaut de portabilité, pas erreur de syntaxe.
        final versionOnly = code == 'invalid-syntax' &&
            RegExp(r'on Python 3\.\d+|added in Python 3\.\d+')
                .hasMatch('${d['message']}');
        if (versionOnly) (cat, sev) = (_por, _h);
        final loc = d['location'] as Map? ?? const {};
        final fix = d['fix'];
        return Finding(
          tool: 'ruff',
          ruleId: code,
          category: cat,
          severity: sev,
          line: jsonInt(loc['row']) ?? 0,
          endLine: jsonInt((d['end_location'] as Map?)?['row']),
          column: jsonInt(loc['column']) ?? 0,
          message: '${d['message']}',
          url: d['url'] as String?,
          equivalents:
              versionOnly ? const ['VERMIN', 'PYRIGHT'] : ruffEquivalents(code),
          edits: [
            if (fix case {'applicability': 'safe', 'edits': final List es})
              for (final e in es.whereType<Map<String, Object?>>())
                if ((e['location'], e['end_location'])
                    case (final Map a, final Map b))
                  TextEdit(
                      jsonInt(a['row']) ?? 1,
                      jsonInt(a['column']) ?? 1,
                      jsonInt(b['row']) ?? 1,
                      jsonInt(b['column']) ?? 1,
                      '${e['content'] ?? ''}',
                      code),
          ],
        );
      }(),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Bandit : sécurité
// ─────────────────────────────────────────────────────────────────────────────

class BanditAnalyzer extends PythonAnalyzer {
  @override
  String get name => 'bandit';

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final r = await ctx.run(tc.executable, [
      '-f',
      'json',
      '-q',
      if (ctx.config.excludedFor(name) case final ex when ex.isNotEmpty) ...[
        '-s',
        ex.join(',')
      ],
      ctx.filePath,
    ]);
    if (r == null) return missing();
    try {
      return ok(parseBandit(r.stdout));
    } on FormatException catch (e) {
      return failed(r.stderr.trim().isEmpty ? e.message : r.stderr.trim());
    }
  }
}

/// Reclassements Bandit, alignés sur Ruff et sur les règles shell : secrets
/// en dur relevés (Bandit les classe Low ; Critical si la valeur ressemble à
/// un vrai secret, voir [parseBandit]), exécution de code ou de données
/// (eval, exec, pickle, yaml.load, SQL concaténé) High comme SEC003,
/// problèmes de robustesse sortis de la catégorie Sécurité.
const Map<String, (Category, Severity)> banditMap = {
  'B105': (_sec, _h),
  'B106': (_sec, _h),
  'B107': (_sec, _h),
  'B102': (_sec, _h), // exec
  'B301': (_sec, _h), // pickle
  'B307': (_sec, _h), // eval
  'B506': (_sec, _h), // yaml.load non sûr
  'B608': (_sec, _h), // SQL construit par concaténation
  'B101': (_rob, _l), // assert
  'B110': (_rob, _l), // try/except/pass
  'B112': (_rob, _l), // try/except/continue
  'B113': (_rob, _m), // requête HTTP sans timeout
};

/// Rapport `bandit -f json` : sévérité Bandit, abaissée d'un cran quand la
/// confiance est faible.
List<Finding> parseBandit(String json) {
  final doc = _decode(json);
  if (doc == null) return [];
  if (doc is! Map || doc['results'] is! List) {
    throw const FormatException('sortie JSON Bandit inattendue');
  }
  return [
    for (final r in (doc['results'] as List).whereType<Map<String, Object?>>())
      () {
        final id = '${r['test_id']}';
        final fixed = banditMap[id];
        var sev = switch ('${r['issue_severity']}'.toUpperCase()) {
          'HIGH' => _h,
          'MEDIUM' => _m,
          _ => _l,
        };
        if ('${r['issue_confidence']}'.toUpperCase() == 'LOW') {
          sev = _lower(sev);
        }
        final num = id.substring(1);
        final secret = const {'B105', 'B106', 'B107'}.contains(id);
        final text = '${r['issue_text']}';
        // Valeur ressemblant à un vrai secret : Critical, comme SEC002.
        if (secret && looksLikeRealSecret(_quoted(text))) sev = _c;
        return Finding(
          tool: 'bandit',
          ruleId: id,
          category: fixed?.$1 ?? _sec,
          severity: secret ? (sev == _c ? _c : fixed!.$2) : (fixed?.$2 ?? sev),
          line: jsonInt(r['line_number']) ?? 0,
          endLine: [
            for (final l in (r['line_range'] as List? ?? const []))
              if (jsonInt(l) case final n?) n
          ].fold<int?>(null, (a, b) => a == null || b > a ? b : a),
          column: (jsonInt(r['col_offset']) ?? -1) + 1,
          // Bandit recopie la valeur du secret après « : » : jamais reproduite.
          message: secret ? text.split(':').first : text,
          url: r['more_info'] as String?,
          refs: [
            if (jsonInt((r['issue_cwe'] as Map?)?['id']) case final int cwe)
              'CWE-$cwe',
          ],
          equivalents: [
            'S$num',
            if (id == 'B307') 'W0123',
            if (secret) ..._secretEquivalents,
          ],
        );
      }(),
  ];
}

/// Valeur entre apostrophes dans un message Bandit (`…: 'valeur'`).
String _quoted(String text) =>
    RegExp(r"'(.*)'\s*$").firstMatch(text)?.group(1) ?? '';

/// Valeur de mot de passe qui ressemble à un vrai secret : au moins 8
/// caractères, sans espace, et pas un exemple ou un gabarit (changeme,
/// `${VAR}`, `<mot de passe>`, `xxxxxxxx`…).
bool looksLikeRealSecret(String v) {
  if (v.length < 8 || v.contains(' ')) return false;
  if (RegExp(r'[{}<>$%]').hasMatch(v)) return false;
  if (v.split('').toSet().length <= 2) return false;
  return !RegExp(
          r'^(?:change[_-]?me|password|passwd|secret|example|default|'
          r'placeholder|dummy|test(?:ing)?|none|null|todo|your[_-]?\w*)\d*$',
          caseSensitive: false)
      .hasMatch(v);
}

// ─────────────────────────────────────────────────────────────────────────────
// Semgrep : règles du registre (p/python)
// ─────────────────────────────────────────────────────────────────────────────

/// Jeu de règles Semgrep (registre semgrep.dev : accès réseau nécessaire).
const semgrepRuleset = 'p/python';

/// Règle Semgrep portant sur un secret : son message peut interpoler la
/// valeur trouvée, et la ligne n'est pas recopiée.
final semgrepSecretRule =
    RegExp(r'secret|password|passwd|token|credential|api-?key|private-key');

/// Téléchargement des règles d'un jeu du registre (null : échec).
typedef RulesFetcher = Future<String?> Function(Uri url);

class SemgrepAnalyzer extends PythonAnalyzer {
  SemgrepAnalyzer({RulesFetcher? fetch, Directory? cacheDir})
      : _fetch = fetch ?? _download,
        _cacheDir = cacheDir;

  final RulesFetcher _fetch;
  final Directory? _cacheDir;

  @override
  String get name => 'semgrep';

  /// Âge au-delà duquel le cache des règles est rafraîchi.
  static const cacheMaxAge = Duration(days: 7);

  /// Dossier du cache : `${XDG_CACHE_HOME:-~/.cache}/check-script`.
  static Directory? defaultCacheDir() {
    final env = Platform.environment;
    final base = env['XDG_CACHE_HOME'] ??
        (env['HOME'] == null ? null : '${env['HOME']}/.cache');
    return base == null ? null : Directory('$base/check-script');
  }

  /// Résolution en cours ou faite (partagée par les analyses parallèles).
  Future<(String, String)>? _resolved;

  /// Règles à passer à `--config`, et libellé du rapport : la clé
  /// `tools.semgrep.config` si elle est définie ; sinon une copie locale de
  /// `p/python`, téléchargée au premier accès et rafraîchie chaque semaine,
  /// qui sert aussi hors ligne ; à défaut, le registre.
  Future<(String, String)> resolveRules(ToolConfig tc) =>
      _resolved ??= _resolve(tc);

  Future<(String, String)> _resolve(ToolConfig tc) async {
    if (tc.config != null) return (tc.config!, tc.config!);
    final dir = _cacheDir ?? defaultCacheDir();
    if (dir == null) return (semgrepRuleset, semgrepRuleset);
    final cache =
        File('${dir.path}/semgrep-${semgrepRuleset.replaceAll('/', '-')}.yaml');
    final age = cache.existsSync()
        ? DateTime.now().difference(cache.lastModifiedSync())
        : null;
    if (age != null && age < cacheMaxAge) {
      return (cache.path, '$semgrepRuleset (cache)');
    }
    final text =
        await _fetch(Uri.parse('https://semgrep.dev/c/$semgrepRuleset'));
    // Le registre répond en YAML ou en JSON selon la requête : les deux sont
    // des fichiers de règles valides (le JSON est du YAML).
    final head = text?.trimLeft() ?? '';
    if (head.startsWith('rules:') ||
        RegExp(r'^\{\s*"rules"\s*:').hasMatch(head)) {
      try {
        await dir.create(recursive: true);
        final tmp = File('${cache.path}.tmp');
        await tmp.writeAsString(text!);
        await tmp.rename(cache.path);
        return (cache.path, semgrepRuleset);
      } on FileSystemException {
        // Cache non inscriptible : le registre sert directement.
      }
    }
    if (age != null) return (cache.path, '$semgrepRuleset (cache ancien)');
    return (semgrepRuleset, semgrepRuleset);
  }

  static Future<String?> _download(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    try {
      final req = await client.getUrl(url);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join();
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    // Le cache n'est géré que pour une exécution réelle des outils.
    final (rules, label) = ctx.runner is ProcessCommandRunner
        ? await resolveRules(tc)
        : (tc.config ?? semgrepRuleset, tc.config ?? semgrepRuleset);
    final r = await ctx.run(tc.executable, [
      'scan',
      '--config=$rules',
      '--json',
      '--metrics=off',
      '--quiet',
      '--disable-version-check',
      for (final e in tc.exclude) '--exclude-rule=$e',
      ctx.filePath,
    ]);
    if (r == null) return missing();
    try {
      final (findings, errors) = parseSemgrep(r.stdout);
      // Registre injoignable (hors ligne) : aucun résultat et des erreurs.
      if (findings.isEmpty && (errors.isNotEmpty || r.exitCode > 1)) {
        return failed(errors.isNotEmpty
            ? errors.first
            : (r.stderr.trim().isEmpty
                ? 'exit ${r.exitCode}'
                : r.stderr.trim()));
      }
      return ok(findings, detail: label);
    } on FormatException {
      return failed(r.stderr.trim().isEmpty
          ? 'exit ${r.exitCode}'
          : r.stderr.trim().split('\n').last);
    }
  }
}

/// Codes Bandit et Ruff (sécurité) : un résultat Semgrep sur la même ligne
/// désigne presque toujours le même défaut.
const _semgrepEquivalents = [
  'B1*', 'B2*', 'B3*', 'B4*', 'B5*', 'B6*', 'B7*', //
  'S1*', 'S2*', 'S3*', 'S4*', 'S5*', 'S6*', 'S7*',
];

/// Références des métadonnées Semgrep : CWE, et catégories OWASP Top 10
/// 2021 (les autres éditions sont ignorées, comme pour les règles intégrées).
List<String> semgrepReferences(Map meta) {
  List<String> strings(Object? v) => [
        for (final e in v is List ? v : (v == null ? const [] : [v])) '$e'
      ];
  return [
    for (final c in strings(meta['cwe']))
      if (RegExp(r'^CWE-(\d+)').firstMatch(c) case final m?) 'CWE-${m[1]}',
    for (final o in strings(meta['owasp']))
      if (RegExp(r'^(A\d\d):2021\b').firstMatch(o) case final m?)
        'OWASP ${m[1]}:2021',
  ];
}

/// Sortie `semgrep --json` : problèmes et messages d'erreur.
(List<Finding>, List<String>) parseSemgrep(String json) {
  final doc = _decode(json);
  if (doc is! Map) {
    throw const FormatException('sortie JSON Semgrep inattendue');
  }
  final errors = [
    for (final e in (doc['errors'] as List? ?? const []).whereType<Map>())
      '${e['message'] ?? e['type'] ?? e}'.trim().split('\n').first,
  ];
  final out = <Finding>[];
  for (final r in (doc['results'] as List? ?? const []).whereType<Map>()) {
    final extra = r['extra'] as Map? ?? const {};
    final meta = extra['metadata'] as Map? ?? const {};
    final start = r['start'] as Map? ?? const {};
    final end = r['end'] as Map? ?? const {};
    final cat = switch ('${meta['category']}'.toLowerCase()) {
      'security' => _sec,
      'correctness' => _rob,
      'performance' => _perf,
      'portability' => _por,
      _ => _mnt,
    };
    var sev = switch ('${extra['severity']}'.toUpperCase()) {
      'ERROR' || 'HIGH' || 'CRITICAL' => _h,
      'WARNING' || 'MEDIUM' => _m,
      _ => _l,
    };
    if ('${meta['confidence']}'.toUpperCase() == 'LOW') sev = _lower(sev);
    final id = '${r['check_id']}'.split('.').last;
    final secret = semgrepSecretRule.hasMatch(id.toLowerCase());
    final fix = extra['fix'];
    final line = jsonInt(start['line']) ?? 0;
    out.add(Finding(
      tool: 'semgrep',
      ruleId: id,
      category: cat,
      severity: sev,
      line: line,
      endLine: jsonInt(end['line']),
      column: jsonInt(start['col']) ?? 0,
      message: secret
          ? 'Potential hard-coded secret (rule $id)'
          : '${extra['message']}'.trim().split('\n').first,
      url: (meta['source'] ?? meta['shortlink']) as String?,
      refs: semgrepReferences(meta),
      equivalents: _semgrepEquivalents,
      edits: [
        if (!secret && fix is String && jsonInt(end['line']) != null)
          TextEdit(line, jsonInt(start['col']) ?? 1, jsonInt(end['line'])!,
              jsonInt(end['col']) ?? 1, fix, id),
      ],
    ));
  }
  return (out, errors);
}

// ─────────────────────────────────────────────────────────────────────────────
// mypy et Pyright : typage
// ─────────────────────────────────────────────────────────────────────────────

class MypyAnalyzer extends PythonAnalyzer {
  @override
  String get name => 'mypy';

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final target = ctx.config.pythonTarget;
    final r = await ctx.run(tc.executable, [
      '--output=json',
      '--no-incremental',
      '--cache-dir=/dev/null', // aucun .mypy_cache à côté du script
      '--ignore-missing-imports',
      '--check-untyped-defs',
      '--no-error-summary',
      // mypy 2 n'accepte plus de cible inférieure à 3.10 : Vermin couvre alors
      // la portabilité, mypy vérifie avec la version de l'interpréteur.
      if (pythonTargetAtLeast(target, 10)) '--python-version=$target',
      for (final e in tc.exclude) '--disable-error-code=$e',
      ctx.filePath,
    ]);
    if (r == null) return missing();
    if (r.exitCode > 1 && r.stdout.trim().isEmpty) {
      return failed(r.stderr.trim().split('\n').last);
    }
    return ok(parseMypy(r.stdout));
  }
}

/// Sortie `mypy --output=json` : un objet JSON par ligne ; les notes (qui
/// complètent l'erreur précédente) sont ignorées.
List<Finding> parseMypy(String output) {
  final out = <Finding>[];
  for (final l in output.split('\n')) {
    if (!l.trimLeft().startsWith('{')) continue;
    final Object? d;
    try {
      d = jsonDecode(l);
    } on FormatException {
      continue;
    }
    if (d is! Map || d['severity'] == 'note') continue;
    final code = '${d['code'] ?? 'misc'}';
    final syntax = code == 'syntax';
    final hint = d['hint'];
    out.add(Finding(
      tool: 'mypy',
      ruleId: code,
      category: _rob,
      severity: syntax ? _c : _m,
      line: jsonInt(d['line']) ?? 0,
      endLine: jsonInt(d['end_line']),
      column: jsonInt(d['column']) ?? 0,
      message: hint is String && hint.isNotEmpty
          ? '${d['message']} ($hint)'
          : '${d['message']}',
      url:
          'https://mypy.readthedocs.io/en/stable/error_code_list.html#code-$code',
      equivalents: [
        'report*',
        if (syntax) ...['SYNTAX', ...pythonSyntaxEquivalents],
      ],
    ));
  }
  return out;
}

class PyrightAnalyzer extends PythonAnalyzer {
  @override
  String get name => 'pyright';

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final r = await ctx.run(tc.executable, [
      '--outputjson',
      '--pythonversion',
      ctx.config.pythonTarget,
      ctx.filePath,
    ]);
    if (r == null) return missing();
    try {
      return ok([
        for (final f in parsePyright(r.stdout))
          if (!tc.exclude.contains(f.ruleId)) f
      ]);
    } on FormatException {
      return failed(r.stderr.trim().isEmpty
          ? 'exit ${r.exitCode}'
          : r.stderr.trim().split('\n').last);
    }
  }
}

/// Sortie `pyright --outputjson` (positions 0-based).
List<Finding> parsePyright(String json) {
  final doc = _decode(json);
  if (doc is! Map) {
    throw const FormatException('sortie JSON Pyright inattendue');
  }
  final out = <Finding>[];
  for (final d
      in (doc['generalDiagnostics'] as List? ?? const []).whereType<Map>()) {
    final sev = switch ('${d['severity']}') {
      'error' => _m,
      'warning' => _l,
      _ => null,
    };
    if (sev == null) continue;
    final start = (d['range'] as Map?)?['start'] as Map? ?? const {};
    final rule = d['rule'] as String?;
    final message = '${d['message']}'.split('\n').first.trim();
    // « … requires Python 3.10 or newer » : portabilité, pas syntaxe.
    final versionOnly =
        rule == null && RegExp(r'Python 3\.\d+').hasMatch(message);
    out.add(Finding(
      tool: 'pyright',
      ruleId: rule ?? 'PYRIGHT',
      category: versionOnly ? _por : _rob,
      severity: versionOnly ? _h : sev,
      line: (jsonInt(start['line']) ?? -1) + 1,
      endLine: switch (
          jsonInt(((d['range'] as Map?)?['end'] as Map?)?['line'])) {
        final n? => n + 1,
        null => null,
      },
      column: (jsonInt(start['character']) ?? -1) + 1,
      message: message,
      url: rule == null
          ? null
          : 'https://microsoft.github.io/pyright/#/configuration?id=$rule',
      equivalents: versionOnly
          ? const ['VERMIN', 'invalid-syntax']
          : (rule == null ? ['SYNTAX', ...pythonSyntaxEquivalents] : const []),
    ));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pylint
// ─────────────────────────────────────────────────────────────────────────────

class PylintAnalyzer extends PythonAnalyzer {
  @override
  String get name => 'pylint';

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final r = await ctx.run(tc.executable, [
      '--output-format=json2',
      '--score=n',
      '--persistent=n',
      '--py-version=${ctx.config.pythonTarget}',
      '--max-line-length=${ctx.config.thresholds.maxLineLength}',
      if (tc.exclude.isNotEmpty) '--disable=${tc.exclude.join(',')}',
      ctx.filePath,
    ]);
    if (r == null) return missing();
    try {
      return ok(parsePylint(r.stdout));
    } on FormatException {
      return failed(r.stderr.trim().isEmpty
          ? 'exit ${r.exitCode}'
          : r.stderr.trim().split('\n').last);
    }
  }
}

/// Reclassements Pylint notables.
const Map<String, (Category, Severity)> pylintMap = {
  'W0122': (_sec, _m), // exec
  'W0123': (_sec, _m), // eval
  'W1510': (_rob, _m), // subprocess.run sans check
  'W0102': (_rob, _m), // argument par défaut mutable
  'W0702': (_rob, _m), // except nu
  'W1514': (_por, _l), // open sans encoding
  'E0602': (_rob, _h), // nom non défini
};

/// Sortie `pylint --output-format=json2`.
List<Finding> parsePylint(String json) {
  final doc = _decode(json);
  if (doc is! Map) throw const FormatException('sortie JSON Pylint inattendue');
  final ruffOf = {for (final e in ruffToPylint.entries) e.value: e.key};
  final out = <Finding>[];
  for (final m in (doc['messages'] as List? ?? const []).whereType<Map>()) {
    final type = '${m['type']}';
    final byType = switch (type) {
      'fatal' => (_rob, _h),
      'error' => (_rob, _m),
      'warning' => (_rob, _l),
      'refactor' || 'convention' => (_mnt, _l),
      _ => null,
    };
    if (byType == null) continue;
    final id = '${m['messageId']}';
    final (cat, sev) = pylintMap[id] ?? byType;
    final syntax = id == 'E0001';
    out.add(Finding(
      tool: 'pylint',
      ruleId: id,
      category: cat,
      severity: syntax ? _c : sev,
      line: jsonInt(m['line']) ?? 0,
      endLine: jsonInt(m['endLine']),
      column: (jsonInt(m['column']) ?? -1) + 1,
      message: '${m['message']}'.split('\n').first,
      url: 'https://pylint.readthedocs.io/en/stable/user_guide/messages/'
          '$type/${m['symbol']}.html',
      equivalents: [
        'PL$id',
        if (ruffOf[id] != null) ruffOf[id]!,
        if (id == 'W0123') ...['B307', 'S307'],
        if (id == 'R0912') 'CC',
        if (syntax) ...['SYNTAX', ...pythonSyntaxEquivalents],
      ],
    ));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Radon : complexité cyclomatique et indice de maintenabilité
// ─────────────────────────────────────────────────────────────────────────────

class RadonAnalyzer extends PythonAnalyzer {
  @override
  String get name => 'radon';

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final exe = ctx.config.tool(name).executable;
    final cc = await ctx.run(exe, ['cc', '-j', '-s', ctx.filePath]);
    if (cc == null) return missing();
    final mi = await ctx.run(exe, ['mi', '-j', '-s', ctx.filePath]);
    try {
      return ok([
        ...parseRadonCc(cc.stdout),
        if (mi != null) ...parseRadonMi(mi.stdout),
      ]);
    } on FormatException catch (e) {
      return failed(e.message);
    }
  }
}

/// Complexité à partir de laquelle une fonction est signalée (rang C).
const radonMinComplexity = 11;

/// `radon cc -j` : fonctions et méthodes de rang C (11-20, Low), D (21-30,
/// Medium), E-F (> 30, High). Un fichier non analysable est ignoré (erreur de
/// syntaxe déjà signalée).
List<Finding> parseRadonCc(String json) {
  final doc = _decode(json);
  if (doc == null) return [];
  if (doc is! Map) throw const FormatException('sortie JSON Radon inattendue');
  final out = <Finding>[];
  void visit(Map b) {
    for (final m in (b['methods'] as List? ?? const []).whereType<Map>()) {
      visit(m);
    }
    if (b['type'] == 'class') return;
    final cc = jsonInt(b['complexity']) ?? 0;
    if (cc < radonMinComplexity) return;
    final rank = '${b['rank']}';
    out.add(Finding(
      tool: 'radon',
      ruleId: 'CC',
      category: _mnt,
      severity: cc > 30 ? _h : (cc > 20 ? _m : _l),
      line: jsonInt(b['lineno']) ?? 0,
      message: 'Cyclomatic complexity of ${b['name']} is $cc (rank $rank)',
      url:
          'https://radon.readthedocs.io/en/latest/intro.html#cyclomatic-complexity',
      equivalents: const ['C901', 'PLR0912', 'R0912'],
    ));
  }

  for (final v in doc.values) {
    if (v is List) {
      for (final b in v.whereType<Map>()) {
        visit(b);
      }
    }
  }
  return out;
}

/// `radon mi -j` : indice de maintenabilité de rang B (10-19, Low) ou C
/// (< 10, Medium).
List<Finding> parseRadonMi(String json) {
  final doc = _decode(json);
  if (doc is! Map) return [];
  final out = <Finding>[];
  for (final v in doc.values.whereType<Map>()) {
    final rank = '${v['rank']}';
    final mi = v['mi'];
    if (mi is! num || rank == 'A') continue;
    out.add(Finding(
      tool: 'radon',
      ruleId: 'MI',
      category: _mnt,
      severity: rank == 'C' ? _m : _l,
      line: 0,
      message: 'Maintainability index is ${mi.toStringAsFixed(1)} (rank $rank)',
      url:
          'https://radon.readthedocs.io/en/latest/intro.html#maintainability-index',
    ));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Vermin : version minimale de Python requise
// ─────────────────────────────────────────────────────────────────────────────

class VerminAnalyzer extends PythonAnalyzer {
  @override
  String get name => 'vermin';

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final target = ctx.config.pythonTarget;
    final r = await ctx.run(ctx.config.tool(name).executable, [
      '--no-tips',
      '--violations',
      '-t=$target-',
      '--format',
      'parsable',
      ctx.filePath,
    ]);
    if (r == null) return missing();
    if (r.exitCode > 1) return failed(r.stderr.trim());
    return ok(parseVermin(r.stdout, target), detail: '≤ $target');
  }
}

/// Sortie `vermin --violations --format parsable` :
/// `fichier:ligne:colonne:py2:py3:fonctionnalité` ; les lignes de synthèse
/// (sans numéro de ligne ni fonctionnalité) sont ignorées.
List<Finding> parseVermin(String output, String target) {
  final re = RegExp(r'^(.*?):(\d+):(\d*):([^:]*):([^:]*):(.+)$');
  final out = <Finding>[];
  for (final l in output.split('\n')) {
    final m = re.firstMatch(l.trim());
    if (m == null) continue;
    final py3 = m[5]!.trim();
    final feature = m[6]!.trim();
    out.add(Finding(
      tool: 'vermin',
      ruleId: 'VERMIN',
      category: _por,
      severity: _h,
      line: int.parse(m[2]!),
      column: int.tryParse(m[3]!) ?? 0,
      message: py3.startsWith('!')
          ? '$feature is not available in Python 3'
          : '$feature requires Python $py3 (target: $target)',
      url: 'https://github.com/netromdk/vermin',
      equivalents: const ['PYRIGHT'],
    ));
  }
  return out;
}
