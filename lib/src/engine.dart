/// Orchestration : exécute les analyseurs, fusionne et dédoublonne leurs
/// résultats, applique directives et configuration, calcule les notes.
library;

import 'dart:io';

import 'analyzers/analyzer.dart';
import 'analyzers/builtin_rules.dart';
import 'analyzers/external_tools.dart';
import 'analyzers/secrets.dart';
import 'analyzers/shellcheck.dart';
import 'baseline.dart';
import 'config.dart';
import 'i18n.dart';
import 'model/finding.dart';
import 'model/report.dart';
import 'rules/catalog.dart';
import 'scoring.dart';
import 'script_info.dart';
import 'suppressions.dart';

/// Analyseurs par ordre de priorité : en cas de doublon sur une même ligne,
/// le résultat de l'outil le plus spécialisé (le premier) est conservé.
List<Analyzer> defaultAnalyzers() => [
      SyntaxAnalyzer(),
      ShellcheckAnalyzer(),
      GitleaksAnalyzer(),
      TrufflehogAnalyzer(),
      CheckbashismsAnalyzer(),
      BuiltinAnalyzer(),
      ShfmtAnalyzer(),
      BashateAnalyzer(),
    ];

/// Étape d'une analyse, pour suivre la progression (interface graphique).
class AnalysisProgress {
  final String script;

  /// Outil en cours (null : analyse terminée).
  final String? tool;
  final int done;
  final int total;

  /// Compte rendu de l'outil qui vient de se terminer, le cas échéant.
  final ToolRun? lastRun;

  const AnalysisProgress(this.script, this.tool, this.done, this.total,
      {this.lastRun});

  double get fraction => total == 0 ? 1 : done / total;
}

class Engine {
  final CheckConfig config;
  final Lang lang;
  final CommandRunner runner;
  final List<Analyzer> analyzers;

  /// Référence facultative : chaque rapport reçoit sa [Comparison].
  final Baseline? baseline;
  final _versions = <String, String?>{};

  Engine({
    this.config = const CheckConfig(),
    this.lang = Lang.fr,
    this.runner = const ProcessCommandRunner(),
    this.baseline,
    List<Analyzer>? analyzers,
  }) : analyzers = analyzers ?? defaultAnalyzers();

  /// Analyse un fichier sur disque.
  Future<ScriptReport> analyzeFile(String path,
      {Dialect? dialect,
      void Function(AnalysisProgress)? onProgress,
      CancelToken? cancel}) async {
    final content = await File(path).readAsString();
    return analyze(
        ScriptInfo.fromContent(path, content, forcedDialect: dialect),
        filePath: path,
        onProgress: onProgress,
        cancel: cancel);
  }

  /// Analyse un contenu. Sans [filePath], le contenu est écrit dans un fichier
  /// temporaire pour les outils externes. Lève [AnalysisCancelled] si
  /// [cancel] est déclenché.
  Future<ScriptReport> analyze(ScriptInfo script,
      {String? filePath,
      void Function(AnalysisProgress)? onProgress,
      CancelToken? cancel}) async {
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
          runner: runner,
          cancel: cancel);
      final runs = <ToolRun>[];
      final raw = <Finding>[];
      final total = analyzers.length;
      for (final a in analyzers) {
        cancel?.check();
        onProgress
            ?.call(AnalysisProgress(script.path, a.name, runs.length, total));
        if (!config.tool(a.name).enabled) {
          runs.add(ToolRun(a.name, ToolStatus.disabled));
          continue;
        }
        final r = await a.analyze(ctx);
        cancel?.check();
        final v = r.run.status == ToolStatus.ok
            ? (_versions.containsKey(a.name)
                ? _versions[a.name]
                : _versions[a.name] = await a.version(runner, config))
            : null;
        final run = v == null
            ? r.run
            : ToolRun(r.run.tool, r.run.status,
                version: v, detail: r.run.detail, findings: r.run.findings);
        runs.add(run);
        raw.addAll(r.findings);
        onProgress?.call(AnalysisProgress(
            script.path, a.name, runs.length, total,
            lastRun: run));
      }

      final suppressions = Suppressions.parse(script.lines);
      final deduped = deduplicate(raw);
      final kept = [
        for (final f in deduped)
          if (!suppressions.suppresses(f)) f
      ];
      final findings = sortFindings(fingerprintAll(
          applyConfig(escalate(enrich(kept, lang), config.contexts), config),
          script.lines));
      final scores = [
        for (final c in Category.values)
          scoreCategory(c, findings, script.codeLines, config.scoring)
      ];
      final report = ScriptReport(
        script: script,
        tools: runs,
        findings: findings,
        scores: scores,
        global: globalScore(scores, config.scoring),
        date: DateTime.now(),
        suppressed: deduped.length - kept.length,
        profile: config.profile.name,
        contexts: [for (final c in config.contexts) c.name],
      );
      onProgress?.call(AnalysisProgress(script.path, null, total, total));
      return report.withComparison(baseline?.compare(report));
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
/// équivalents de l'autre, ou qu'ils ont le même outil et le même code.
///
/// Une erreur de syntaxe (`SYNTAX`) couvre tout le fichier : les outils
/// situent souvent la même erreur sur des lignes différentes.
bool isDuplicate(Finding a, Finding b) {
  final eq = a.equivalents.any((p) => _matches(p, b.ruleId)) ||
      b.equivalents.any((p) => _matches(p, a.ruleId));
  if (a.tool == b.tool) {
    return a.line == b.line && (a.ruleId == b.ruleId || eq);
  }
  final sameLine = a.line == b.line ||
      a.line == 0 ||
      b.line == 0 ||
      a.ruleId == 'SYNTAX' ||
      b.ruleId == 'SYNTAX';
  return sameLine && eq;
}

/// Conserve le premier de chaque groupe de doublons (ordre des analyseurs).
List<Finding> deduplicate(List<Finding> findings) {
  final kept = <Finding>[];
  for (final f in findings) {
    if (!kept.any((k) => isDuplicate(k, f))) kept.add(f);
  }
  return kept;
}

/// Complète conseils et liens de documentation manquants.
List<Finding> enrich(List<Finding> findings, Lang lang) => [
      for (final f in findings)
        f.hint != null && f.url != null
            ? f
            : f.copyWith(
                hint: f.hint ?? toolHint(f, lang), url: f.url ?? ruleUrl(f)),
    ];

/// Lien de documentation d'une règle d'outil externe.
String? ruleUrl(Finding f) => switch (f.tool) {
      'shellcheck' => 'https://www.shellcheck.net/wiki/${f.ruleId}',
      'bashate' => 'https://docs.openstack.org/bashate/latest/man/bashate.html',
      'checkbashisms' => 'https://manpages.debian.org/checkbashisms',
      'shfmt' =>
        'https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd',
      'gitleaks' => 'https://github.com/gitleaks/gitleaks',
      'trufflehog' => 'https://github.com/trufflesecurity/trufflehog',
      _ => null,
    };

/// Conseil générique pour les outils externes sans conseil propre.
String? toolHint(Finding f, Lang lang) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  return switch ((f.tool, f.ruleId)) {
    ('shfmt', 'FORMAT') => t(
        'Reformater avec check-script --fix (ou shfmt -w).',
        'Reformat with check-script --fix (or shfmt -w).'),
    ('shfmt', 'DIALECT') || ('checkbashisms', _) => t(
        'Utiliser l\'équivalent POSIX, ou déclarer #!/usr/bin/env bash.',
        'Use the POSIX equivalent, or declare #!/usr/bin/env bash.'),
    ('syntax', _) || ('shfmt', 'PARSE') => t(
        'Corriger la syntaxe : le script ne peut pas s\'exécuter.',
        'Fix the syntax: the script cannot run.'),
    ('gitleaks' || 'trufflehog', _) => t(
        'Retirer le secret du script, le révoquer et le stocker hors du code.',
        'Remove the secret from the script, revoke it and store it outside the code.'),
    _ => null,
  };
}

/// Relève les sévérités selon les contextes d'exécution déclarés.
List<Finding> escalate(List<Finding> findings, Set<ExecContext> contexts) {
  if (contexts.isEmpty) return findings;
  return [
    for (final f in findings)
      () {
        var sev = f.severity;
        for (final c in contexts) {
          final s = contextEscalations[c]?[f.ruleId];
          if (s != null && s.index < sev.index) sev = s;
        }
        return sev == f.severity ? f : f.copyWith(severity: sev);
      }(),
  ];
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
