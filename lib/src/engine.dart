/// Orchestration : exécute les analyseurs, fusionne et dédoublonne leurs
/// résultats, applique la configuration et calcule les notes.
library;

import 'dart:io';

import 'analyzers/analyzer.dart';
import 'analyzers/builtin_rules.dart';
import 'analyzers/external_tools.dart';
import 'analyzers/shellcheck.dart';
import 'config.dart';
import 'i18n.dart';
import 'model/finding.dart';
import 'model/report.dart';
import 'scoring.dart';
import 'script_info.dart';

/// Analyseurs par ordre de priorité : en cas de doublon sur une même ligne,
/// le résultat de l'outil le plus spécialisé (le premier) est conservé.
List<Analyzer> defaultAnalyzers() => [
      SyntaxAnalyzer(),
      ShellcheckAnalyzer(),
      CheckbashismsAnalyzer(),
      BuiltinAnalyzer(),
      ShfmtAnalyzer(),
      BashateAnalyzer(),
    ];

class Engine {
  final CheckConfig config;
  final Lang lang;
  final CommandRunner runner;
  final List<Analyzer> analyzers;
  final _versions = <String, String?>{};

  Engine({
    this.config = const CheckConfig(),
    this.lang = Lang.fr,
    this.runner = const ProcessCommandRunner(),
    List<Analyzer>? analyzers,
  }) : analyzers = analyzers ?? defaultAnalyzers();

  /// Analyse un fichier sur disque.
  Future<ScriptReport> analyzeFile(String path, {Dialect? dialect}) async {
    final content = await File(path).readAsString();
    return analyze(
        ScriptInfo.fromContent(path, content, forcedDialect: dialect),
        filePath: path);
  }

  /// Analyse un contenu. Sans [filePath], le contenu est écrit dans un fichier
  /// temporaire pour les outils externes.
  Future<ScriptReport> analyze(ScriptInfo script, {String? filePath}) async {
    Directory? tmp;
    var path = filePath;
    if (path == null) {
      tmp = await Directory.systemTemp.createTemp('check_script_');
      path = '${tmp.path}/script.sh';
      await File(path).writeAsString(script.content);
    }
    try {
      final ctx = AnalysisContext(
          script: script,
          filePath: path,
          config: config,
          lang: lang,
          runner: runner);
      final runs = <ToolRun>[];
      final raw = <Finding>[];
      for (final a in analyzers) {
        if (!config.tool(a.name).enabled) {
          runs.add(ToolRun(a.name, ToolStatus.disabled));
          continue;
        }
        final r = await a.analyze(ctx);
        final v = r.run.status == ToolStatus.ok
            ? (_versions.containsKey(a.name)
                ? _versions[a.name]
                : _versions[a.name] = await a.version(runner, config))
            : null;
        runs.add(v == null
            ? r.run
            : ToolRun(r.run.tool, r.run.status,
                version: v, detail: r.run.detail, findings: r.run.findings));
        raw.addAll(r.findings);
      }
      final findings = sortFindings(applyConfig(deduplicate(raw), config));
      final scores = [
        for (final c in Category.values)
          scoreCategory(c, findings, script.codeLines, config.scoring)
      ];
      return ScriptReport(
        script: script,
        tools: runs,
        findings: findings,
        scores: scores,
        global: globalScore(scores, config.scoring),
        date: DateTime.now(),
      );
    } finally {
      await tmp?.delete(recursive: true);
    }
  }
}

bool _matches(String pattern, String id) => pattern.endsWith('*')
    ? id.startsWith(pattern.substring(0, pattern.length - 1))
    : pattern == id;

/// Deux problèmes sont des doublons s'ils portent sur la même ligne (ou si
/// l'un concerne le fichier entier) et que le code de l'un figure parmi les
/// équivalents de l'autre (ou qu'ils ont le même outil et le même code).
///
/// Une erreur de syntaxe (`SYNTAX`) couvre tout le fichier : les outils
/// situent souvent la même erreur sur des lignes différentes.
bool isDuplicate(Finding a, Finding b) {
  final sameLine = a.line == b.line ||
      a.line == 0 ||
      b.line == 0 ||
      a.ruleId == 'SYNTAX' ||
      b.ruleId == 'SYNTAX';
  if (!sameLine) return false;
  if (a.tool == b.tool) return a.ruleId == b.ruleId && a.line == b.line;
  return a.equivalents.any((p) => _matches(p, b.ruleId)) ||
      b.equivalents.any((p) => _matches(p, a.ruleId));
}

/// Conserve le premier de chaque groupe de doublons (ordre des analyseurs).
List<Finding> deduplicate(List<Finding> findings) {
  final kept = <Finding>[];
  for (final f in findings) {
    if (!kept.any((k) => isDuplicate(k, f))) kept.add(f);
  }
  return kept;
}

/// Retire les règles désactivées et applique les reclassements.
List<Finding> applyConfig(List<Finding> findings, CheckConfig config) => [
      for (final f in findings)
        if (!config.disabledRules.contains(f.ruleId.toUpperCase()))
          () {
            final o = config.overrides[f.ruleId.toUpperCase()];
            return o == null
                ? f
                : f.copyWith(category: o.category, severity: o.severity);
          }(),
    ];

List<Finding> sortFindings(List<Finding> findings) =>
    [...findings]..sort((a, b) {
        var c = a.category.index.compareTo(b.category.index);
        if (c != 0) return c;
        c = a.severity.index.compareTo(b.severity.index);
        if (c != 0) return c;
        return a.line.compareTo(b.line);
      });
