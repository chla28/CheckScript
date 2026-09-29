/// Outils propres aux fichiers hôtes de scripts : hadolint (Dockerfile),
/// actionlint et zizmor (workflows GitHub Actions). Ils lisent le fichier
/// entier sur l'entrée standard ; leurs lignes sont celles du fichier.
library;

import 'dart:convert';

import '../config.dart';
import '../embedded.dart';
import '../model/finding.dart';
import '../script_info.dart';
import 'analyzer.dart';

const _sec = Category.security;
const _rob = Category.robustness;
const _mnt = Category.maintainability;
const _perf = Category.performance;

String _host(ScriptInfo s) => '${s.displayLines.join('\n')}\n';

abstract class _HostTool extends Analyzer {
  EmbeddedKind get kind;

  @override
  ToolLanguage get language => ToolLanguage.any;

  @override
  bool appliesTo(ScriptInfo script) => script.embedded?.kind == kind;

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    return r == null ? null : extractVersion('${r.stdout}${r.stderr}') ?? '?';
  }

  /// Arguments de l'outil (fichier lu sur l'entrée standard).
  List<String> args(AnalysisContext ctx);

  List<Finding> parse(String stdout);

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final r = await ctx.run(ctx.config.tool(name).executable, args(ctx),
        stdin: _host(ctx.script));
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    try {
      final f = parse(r.stdout);
      return AnalyzerResult(
          ToolRun(name, ToolStatus.ok, findings: f.length), f);
    } on FormatException {
      final detail = r.stderr.trim().split('\n').last;
      return AnalyzerResult(ToolRun(name, ToolStatus.failed,
          detail: detail.isEmpty ? 'exit ${r.exitCode}' : detail));
    }
  }
}

List<Object?> _jsonList(String out) {
  final t = out.trim();
  if (t.isEmpty) return const [];
  final j = jsonDecode(t);
  if (j is! List) throw const FormatException('liste JSON attendue');
  return j;
}

// ── hadolint ────────────────────────────────────────────────────────────────

/// Classement des codes hadolint notables (les autres : Maintenabilité),
/// et règles intégrées équivalentes.
const Map<String, (Category, List<String>)> hadolintMap = {
  'DL3002': (_sec, ['DKR002']), // dernier USER root
  'DL3004': (_sec, []), // sudo
  'DL3006': (_sec, ['DKR001']), // image sans tag
  'DL3007': (_sec, ['DKR001']), // latest
  'DL3008': (_sec, []), // apt sans version
  'DL3013': (_sec, ['SEC024']), // pip sans version
  'DL3016': (_sec, ['SEC024']), // npm sans version
  'DL3018': (_sec, []), // apk sans version
  'DL3028': (_sec, ['SEC024']), // gem sans version
  'DL3033': (_sec, []), // yum sans version
  'DL3037': (_sec, []), // zypper sans version
  'DL3041': (_sec, []), // dnf sans version
  'DL3064': (_sec, ['DKR005']), // données sensibles dans ARG / ENV
  'DL3020': (_mnt, ['DKR004']), // ADD au lieu de COPY
  'DL3003': (_rob, ['ROB005', 'SC2164']), // cd
  'DL4006': (_rob, ['ROB002']), // pipefail
  'DL3009': (_perf, ['DKR007']), // listes apt
  'DL3015': (_sec, ['DKR006']), // --no-install-recommends
  'DL3019': (_perf, ['DKR007']), // apk --no-cache
  'DL3040': (_perf, ['DKR007']), // dnf clean all
  'DL3032': (_perf, ['DKR007']), // yum clean all
  'DL3042': (_perf, []), // pip --no-cache-dir
  'DL3060': (_perf, []), // yarn cache clean
};

class HadolintAnalyzer extends _HostTool {
  @override
  String get name => 'hadolint';
  @override
  EmbeddedKind get kind => EmbeddedKind.dockerfile;

  @override
  List<String> args(AnalysisContext ctx) =>
      ['--format', 'json', '--no-fail', '-'];

  @override
  List<Finding> parse(String stdout) => parseHadolint(stdout);
}

/// Sortie `hadolint --format json` ; les codes ShellCheck (SCxxxx) que
/// hadolint recopie sont écartés : ShellCheck est lancé à part.
List<Finding> parseHadolint(String json) => [
      for (final r in _jsonList(json).whereType<Map>())
        if (!'${r['code']}'.startsWith('SC'))
          () {
            final code = '${r['code']}';
            final m = hadolintMap[code];
            return Finding(
              tool: 'hadolint',
              ruleId: code,
              category: m?.$1 ?? _mnt,
              severity: switch ('${r['level']}') {
                'error' => Severity.high,
                'warning' => Severity.medium,
                _ => Severity.low,
              },
              line: (r['line'] as num?)?.toInt() ?? 0,
              column: (r['column'] as num?)?.toInt() ?? 0,
              message: '${r['message']}',
              url: code.startsWith('DL')
                  ? 'https://github.com/hadolint/hadolint/wiki/$code'
                  : null,
              equivalents: m?.$2 ?? const [],
            );
          }(),
    ];

// ── actionlint ──────────────────────────────────────────────────────────────

/// Catégories actionlint touchant la sécurité.
const _actionlintSecurity = {'expression', 'credentials', 'permissions'};

class ActionlintAnalyzer extends _HostTool {
  @override
  String get name => 'actionlint';
  @override
  EmbeddedKind get kind => EmbeddedKind.githubActions;

  /// actionlint ne vérifie que les workflows, pas les métadonnées d'une
  /// action (action.yml).
  @override
  bool appliesTo(ScriptInfo script) =>
      super.appliesTo(script) &&
      !RegExp(r'(?:^|/)action\.ya?ml$').hasMatch(script.path);

  @override
  List<String> args(AnalysisContext ctx) => [
        '-format',
        '{{json .}}',
        '-no-color',
        '-stdin-filename',
        ctx.script.path.split('/').last,
        '-',
      ];

  @override
  List<Finding> parse(String stdout) => parseActionlint(stdout);
}

/// Sortie `actionlint -format '{{json .}}'` ; les résultats de ShellCheck
/// et pyflakes relayés par actionlint sont écartés (outils lancés à part).
List<Finding> parseActionlint(String json) => [
      for (final r in _jsonList(json).whereType<Map>())
        if (!const {'shellcheck', 'pyflakes'}.contains(r['kind']))
          () {
            final kind = '${r['kind']}';
            final msg = '${r['message']}';
            final untrusted = msg.contains('potentially untrusted');
            final security = _actionlintSecurity.contains(kind) &&
                (kind != 'expression' || untrusted);
            return Finding(
              tool: 'actionlint',
              ruleId: kind,
              category: security ? _sec : _rob,
              severity: untrusted ? Severity.critical : Severity.medium,
              line: (r['line'] as num?)?.toInt() ?? 0,
              column: (r['column'] as num?)?.toInt() ?? 0,
              message: msg.split(' see https://').first,
              url:
                  'https://github.com/rhysd/actionlint/blob/main/docs/checks.md',
              equivalents: untrusted ? const ['SEC023'] : const [],
            );
          }(),
    ];

// ── zizmor ──────────────────────────────────────────────────────────────────

/// Audits zizmor et règles intégrées équivalentes.
const Map<String, List<String>> zizmorEquivalents = {
  'unpinned-uses': ['CI001'],
  'template-injection': ['SEC023'],
  'dangerous-triggers': ['CI003'],
  'excessive-permissions': ['CI002'],
  'hardcoded-container-credentials': ['CI004'],
  'unpinned-images': ['CI005'],
};

class ZizmorAnalyzer extends _HostTool {
  @override
  String get name => 'zizmor';
  @override
  EmbeddedKind get kind => EmbeddedKind.githubActions;

  /// Sans accès réseau : les audits qui interrogent GitHub sont omis.
  @override
  List<String> args(AnalysisContext ctx) =>
      ['--format', 'json', '--offline', '--no-progress', '-'];

  @override
  List<Finding> parse(String stdout) => parseZizmor(stdout);
}

/// Sortie `zizmor --format json` (lignes 0-based) ; une confiance faible
/// abaisse la sévérité d'un cran.
List<Finding> parseZizmor(String json) {
  final out = <Finding>[];
  for (final r in _jsonList(json).whereType<Map>()) {
    final det = r['determinations'] as Map? ?? const {};
    var sev = switch ('${det['severity']}') {
      'High' => Severity.high,
      'Medium' => Severity.medium,
      _ => Severity.low,
    };
    if ('${det['confidence']}' == 'Low' && sev != Severity.low) {
      sev = Severity.values[sev.index + 1];
    }
    final locations = (r['locations'] as List? ?? const []).whereType<Map>();
    final primary = locations.firstWhere(
        (l) => (l['symbolic'] as Map?)?['kind'] == 'Primary',
        orElse: () => locations.isEmpty ? const {} : locations.first);
    final start = ((primary['concrete'] as Map?)?['location']
        as Map?)?['start_point'] as Map?;
    final note = (primary['symbolic'] as Map?)?['annotation'];
    final ident = '${r['ident']}';
    out.add(Finding(
      tool: 'zizmor',
      ruleId: ident,
      category: _sec,
      severity: sev,
      line: ((start?['row'] as num?)?.toInt() ?? -1) + 1,
      column: ((start?['column'] as num?)?.toInt() ?? -1) + 1,
      message: note == null ? '${r['desc']}' : '${r['desc']} ($note)',
      url: r['url'] as String?,
      equivalents: zizmorEquivalents[ident] ?? const [],
    ));
  }
  return out;
}
