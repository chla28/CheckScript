/// Détecteurs de secrets externes : gitleaks et trufflehog (facultatifs).
///
/// Les secrets trouvés ne sont jamais recopiés dans le rapport : seuls le type
/// de secret et la ligne sont conservés. trufflehog est lancé avec
/// `--no-verification` pour qu'aucun secret ne soit envoyé sur le réseau.
library;

import 'dart:convert';

import '../config.dart';
import '../model/finding.dart';
import 'analyzer.dart';

const _secretEquivalents = [
  'SEC002',
  'SEC022',
  'SEC021',
  'SEC010',
  'GL*',
  'TH*'
];

class GitleaksAnalyzer extends Analyzer {
  @override
  String get name => 'gitleaks';

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['version']);
    return r == null ? null : extractVersion(r.stdout) ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final r = await ctx.run(tc.executable, [
      'detect',
      '--no-git',
      '--no-banner',
      '--redact',
      '--exit-code=0',
      '--report-format=json',
      '--report-path=/dev/stdout',
      '--source=${ctx.filePath}',
    ]);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    try {
      final f = parseGitleaks(r.stdout);
      return AnalyzerResult(
          ToolRun(name, ToolStatus.ok, findings: f.length), f);
    } on FormatException catch (e) {
      return AnalyzerResult(ToolRun(name, ToolStatus.failed,
          detail: r.stderr.trim().isEmpty ? e.message : r.stderr.trim()));
    }
  }
}

/// Rapport JSON de gitleaks (tableau d'objets `RuleID`, `StartLine`,
/// `Description`…). Le texte peut être précédé de journaux : on isole le
/// tableau JSON.
List<Finding> parseGitleaks(String output) {
  final start = output.indexOf('[');
  if (start < 0) {
    if (output.trim().isEmpty) return const [];
    throw const FormatException('sortie gitleaks inattendue');
  }
  final Object? doc;
  try {
    doc = jsonDecode(output.substring(start, output.lastIndexOf(']') + 1));
  } on FormatException {
    throw const FormatException('JSON gitleaks invalide');
  }
  return [
    for (final l in (doc as List).whereType<Map>())
      Finding(
        tool: 'gitleaks',
        ruleId: 'GL:${l['RuleID']}',
        category: Category.security,
        severity: Severity.critical,
        line: (l['StartLine'] as num?)?.toInt() ?? 0,
        column: (l['StartColumn'] as num?)?.toInt() ?? 0,
        message: 'Secret detected: ${l['Description'] ?? l['RuleID']}',
        equivalents: _secretEquivalents,
      ),
  ];
}

class TrufflehogAnalyzer extends Analyzer {
  @override
  String get name => 'trufflehog';

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    return r == null ? null : extractVersion('${r.stdout}${r.stderr}') ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final r = await ctx.run(tc.executable, [
      'filesystem',
      ctx.filePath,
      '--json',
      '--no-update',
      '--no-verification',
    ]);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    final f = parseTrufflehog(r.stdout);
    return AnalyzerResult(ToolRun(name, ToolStatus.ok, findings: f.length), f);
  }
}

/// Sortie JSON Lines de trufflehog v3 ; les lignes non JSON (journaux) sont
/// ignorées.
List<Finding> parseTrufflehog(String output) {
  final out = <Finding>[];
  for (final line in const LineSplitter().convert(output)) {
    final t = line.trim();
    if (!t.startsWith('{')) continue;
    final Object? j;
    try {
      j = jsonDecode(t);
    } on FormatException {
      continue;
    }
    if (j is! Map || j['DetectorName'] == null) continue;
    final fs =
        ((j['SourceMetadata'] as Map?)?['Data'] as Map?)?['Filesystem'] as Map?;
    final verified = j['Verified'] == true;
    out.add(Finding(
      tool: 'trufflehog',
      ruleId: 'TH:${j['DetectorName']}',
      category: Category.security,
      severity: verified ? Severity.critical : Severity.high,
      line: (fs?['line'] as num?)?.toInt() ?? 0,
      message:
          '${verified ? 'Verified' : 'Potential'} secret: ${j['DetectorName']}',
      equivalents: _secretEquivalents,
    ));
  }
  return out;
}
