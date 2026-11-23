/// Outils du SDK Dart pour les scripts et sources Dart / Flutter :
/// `dart analyze` (analyseur officiel, lints compris) et `dart format`
/// (contrôle du formatage). Le contrôle syntaxique est celui de
/// [SyntaxAnalyzer] (`dart format`).
library;

import 'package:path/path.dart' as p;

import '../config.dart';
import '../model/finding.dart';
import 'analyzer.dart';

/// Version du SDK : `Dart SDK version: 3.14.0 (stable) …`.
Future<String?> _dartVersion(CommandRunner runner, String executable) async {
  final r = await runner.run(executable, ['--version']);
  return r == null ? null : extractVersion('${r.stdout}${r.stderr}') ?? '?';
}

// ─────────────────────────────────────────────────────────────────────────────
// dart analyze
// ─────────────────────────────────────────────────────────────────────────────

class DartAnalyzeAnalyzer extends Analyzer {
  @override
  String get name => 'dart-analyze';

  @override
  ToolLanguage get language => ToolLanguage.dart;

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) =>
      _dartVersion(runner, config.tool(name).executable);

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final r = await ctx.run(tc.executable, [
      'analyze',
      '--format=machine',
      ctx.filePath,
    ]);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    // Contenu analysé hors du projet (entrée standard, version indexée) : les
    // paquets ne se résolvent pas, les erreurs qui en découlent sont du bruit.
    final detached = p.normalize(ctx.filePath) != p.normalize(ctx.script.path);
    final excluded = {for (final e in tc.exclude) e.toUpperCase()};
    final findings = [
      for (final f in parseDartAnalyze(r.stdout, detached: detached))
        if (!excluded.contains(f.ruleId.toUpperCase())) f
    ];
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok, findings: findings.length), findings);
  }
}

/// Codes d'erreur qui découlent d'un paquet non résolu (analyse hors projet).
bool _unresolvedCascade(String code) =>
    code == 'URI_DOES_NOT_EXIST' ||
    code.startsWith('UNDEFINED_') ||
    const {
      'NON_TYPE_AS_TYPE_ARGUMENT',
      'EXTENDS_NON_CLASS',
      'IMPLEMENTS_NON_CLASS',
      'MIXIN_OF_NON_CLASS',
      'NOT_A_TYPE',
      'INVALID_ANNOTATION',
      'CAST_TO_NON_TYPE',
    }.contains(code);

/// Classement des lints et diagnostics courants (le reste : selon le niveau).
const Map<String, (Category, Severity)> dartLintMap = {
  // Robustesse
  'use_build_context_synchronously': (Category.robustness, Severity.medium),
  'unawaited_futures': (Category.robustness, Severity.medium),
  'discarded_futures': (Category.robustness, Severity.medium),
  'avoid_slow_async_io': (Category.performance, Severity.low),
  'empty_catches': (Category.robustness, Severity.low),
  'control_flow_in_finally': (Category.robustness, Severity.medium),
  'close_sinks': (Category.robustness, Severity.medium),
  'cancel_subscriptions': (Category.robustness, Severity.medium),
  'avoid_dynamic_calls': (Category.robustness, Severity.low),
  'null_check_on_nullable_type_parameter': (
    Category.robustness,
    Severity.medium
  ),
  // Sécurité
  'unsafe_html': (Category.security, Severity.medium),
  'avoid_web_libraries_in_flutter': (Category.portability, Severity.medium),
  // Performance
  'prefer_const_constructors': (Category.performance, Severity.low),
  'prefer_const_declarations': (Category.performance, Severity.low),
  'prefer_const_literals_to_create_immutables': (
    Category.performance,
    Severity.low
  ),
  'prefer_final_fields': (Category.performance, Severity.low),
  'avoid_unnecessary_containers': (Category.performance, Severity.low),
  'sized_box_for_whitespace': (Category.performance, Severity.low),
  // Maintenabilité
  'avoid_print': (Category.maintainability, Severity.low),
  'unused_import': (Category.maintainability, Severity.low),
  'unused_local_variable': (Category.maintainability, Severity.low),
  'unused_element': (Category.maintainability, Severity.low),
  'unused_field': (Category.maintainability, Severity.low),
  'dead_code': (Category.maintainability, Severity.low),
  'deprecated_member_use': (Category.maintainability, Severity.low),
  'deprecated_member_use_from_same_package': (
    Category.maintainability,
    Severity.low
  ),
  // Portabilité
  'depend_on_referenced_packages': (Category.portability, Severity.medium),
};

/// Sortie `--format=machine` : une ligne par diagnostic,
/// `SÉVÉRITÉ|TYPE|CODE|FICHIER|LIGNE|COLONNE|LONGUEUR|MESSAGE`, avec `\|` et
/// `\\` échappés. Les erreurs de syntaxe (`SYNTACTIC_ERROR`) sont écartées :
/// le contrôle syntaxique les rapporte déjà. Avec [detached], les erreurs
/// dues à des paquets non résolus sont écartées aussi.
List<Finding> parseDartAnalyze(String output, {bool detached = false}) {
  final out = <Finding>[];
  for (final raw in output.split('\n')) {
    final parts = _splitMachine(raw.trimRight());
    if (parts == null) continue;
    final (severity, type, code, line, column, message) = parts;
    if (type == 'SYNTACTIC_ERROR') continue;
    if (detached && _unresolvedCascade(code)) continue;
    final key = code.toLowerCase();
    final mapped = dartLintMap[key];
    final (Category cat, Severity sev) = mapped ??
        switch (severity) {
          'ERROR' => (Category.robustness, Severity.high),
          'WARNING' => (Category.robustness, Severity.medium),
          _ => (Category.maintainability, Severity.low),
        };
    out.add(Finding(
      tool: 'dart-analyze',
      // Les lints portent leur nom usuel (`avoid_print`), les diagnostics
      // du compilateur leur code en majuscules.
      ruleId: type == 'LINT' ? key : code,
      category: cat,
      severity: sev,
      line: line,
      column: column,
      message: message,
      url: type == 'LINT' ? 'https://dart.dev/tools/linter-rules/$key' : null,
    ));
  }
  return out;
}

/// Découpe une ligne du format machine ; null si ce n'en est pas une.
(String, String, String, int, int, String)? _splitMachine(String l) {
  final fields = <String>[];
  final b = StringBuffer();
  for (var i = 0; i < l.length; i++) {
    final c = l[i];
    if (c == r'\' && i + 1 < l.length) {
      b.write(l[i + 1]);
      i++;
    } else if (c == '|' && fields.length < 7) {
      fields.add(b.toString());
      b.clear();
    } else {
      b.write(c);
    }
  }
  if (fields.length < 7) return null;
  final rest = b.toString(); // le message
  final line = int.tryParse(fields[4]);
  final column = int.tryParse(fields[5]);
  if (line == null || column == null) return null;
  if (!const {'ERROR', 'WARNING', 'INFO'}.contains(fields[0])) return null;
  return (fields[0], fields[1], fields[2], line, column, rest);
}

// ─────────────────────────────────────────────────────────────────────────────
// dart format
// ─────────────────────────────────────────────────────────────────────────────

class DartFormatAnalyzer extends Analyzer {
  @override
  String get name => 'dart-format';

  @override
  ToolLanguage get language => ToolLanguage.dart;

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) =>
      _dartVersion(runner, config.tool(name).executable);

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final r = await ctx.run(tc.executable,
        ['format', '--output=none', '--set-exit-if-changed', ctx.filePath]);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    // Code 1 : fichier à reformater. Code 65 : erreur de syntaxe, déjà
    // rapportée par le contrôle syntaxique.
    final findings = r.exitCode == 1
        ? [
            const Finding(
              tool: 'dart-format',
              ruleId: 'FORMAT',
              category: Category.maintainability,
              severity: Severity.low,
              line: 0,
              message: 'Fichier non formaté (dart format).',
              url: 'https://dart.dev/tools/dart-format',
            )
          ]
        : <Finding>[];
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok, findings: findings.length), findings);
  }
}
