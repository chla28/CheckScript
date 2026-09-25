/// Orchestration : exécute les analyseurs, fusionne et dédoublonne leurs
/// résultats, applique directives et configuration, calcule les notes.
library;

import 'dart:io';

import 'analyzers/analyzer.dart';
import 'analyzers/builtin_rules.dart';
import 'analyzers/external_tools.dart';
import 'analyzers/python_deps.dart';
import 'analyzers/python_tools.dart';
import 'analyzers/secrets.dart';
import 'analyzers/shellcheck.dart';
import 'baseline.dart';
import 'config.dart';
import 'embedded.dart';
import 'explain.dart';
import 'fixer.dart';
import 'i18n.dart';
import 'model/finding.dart';
import 'model/report.dart';
import 'result_cache.dart';
import 'rules/custom_rules.dart';
import 'version.dart';
import 'rules/catalog.dart';
import 'scoring.dart';
import 'script_info.dart';
import 'suppressions.dart';

/// Analyseurs par ordre de priorité : en cas de doublon sur une même ligne,
/// le résultat de l'outil le plus spécialisé (le premier) est conservé.
/// Seuls ceux du langage du script sont exécutés ([Analyzer.language]).
List<Analyzer> defaultAnalyzers() => [
      SyntaxAnalyzer(),
      ShellcheckAnalyzer(),
      BanditAnalyzer(),
      RuffAnalyzer(),
      SemgrepAnalyzer(),
      MypyAnalyzer(),
      PyrightAnalyzer(),
      PylintAnalyzer(),
      VerminAnalyzer(),
      RadonAnalyzer(),
      PythonDepsAnalyzer(),
      PipAuditAnalyzer(),
      GitleaksAnalyzer(),
      TrufflehogAnalyzer(),
      CheckbashismsAnalyzer(),
      BuiltinAnalyzer(),
      CustomRulesAnalyzer(),
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

  /// Versions des outils, demandées une seule fois (y compris quand
  /// plusieurs analyses tournent en parallèle).
  final _versions = <String, Future<String?>>{};

  /// Outils d'un même script lancés en parallèle (sinon l'un après l'autre).
  final bool parallel;

  /// Cache des résultats (null : toujours réanalyser).
  final ResultCache? cache;

  Engine({
    this.config = const CheckConfig(),
    this.lang = Lang.fr,
    this.runner = const ProcessCommandRunner(),
    this.baseline,
    this.parallel = true,
    this.cache,
    List<Analyzer>? analyzers,
  }) : analyzers = analyzers ?? defaultAnalyzers();

  /// Nombre de scripts analysés simultanément dans un dossier : chaque
  /// analyse lance déjà ses outils en parallèle.
  static int get defaultJobs => (Platform.numberOfProcessors ~/ 4).clamp(1, 4);

  /// Analyse [paths] avec au plus [jobs] scripts à la fois ; les rapports
  /// sont dans l'ordre de [paths]. Un fichier illisible ou non textuel est
  /// passé ([onSkip]). [onDone] est appelé à chaque script terminé.
  Future<List<ScriptReport>> analyzeFiles(List<String> paths,
      {int? jobs,
      CancelToken? cancel,
      void Function(String path, Object error)? onSkip,
      void Function(int done, int total, String path)? onDone}) async {
    final out = List<ScriptReport?>.filled(paths.length, null);
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < paths.length) {
        cancel?.check();
        final i = next++;
        try {
          out[i] = await analyzeFile(paths[i], cancel: cancel);
        } on FileSystemException catch (e) {
          onSkip?.call(paths[i], e);
        } on FormatException catch (e) {
          onSkip?.call(paths[i], e);
        }
        onDone?.call(++done, paths.length, paths[i]);
      }
    }

    final n = (jobs ?? defaultJobs).clamp(1, paths.isEmpty ? 1 : paths.length);
    await Future.wait([for (var w = 0; w < n; w++) worker()], eagerError: true);
    return [
      for (final r in out)
        if (r != null) r
    ];
  }

  /// Analyseurs du langage de [script].
  /// Analyseurs du langage de [script] (sans Bashate pour les scripts
  /// intégrés : leur mise en forme est celle du fichier hôte).
  List<Analyzer> analyzersFor(ScriptInfo script) => [
        for (final a in analyzers)
          if (a.language.accepts(script) &&
              !(script.embedded != null && a.name == 'bashate') &&
              !(a.name == 'custom' && config.customRules.isEmpty))
            a
      ];

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
  /// Clé du cache pour [script] : tout ce qui peut changer le rapport
  /// (contenu, chemin, configuration, langue, versions de check-script et
  /// des outils, règles Semgrep en cache). Null si le cache est inutilisable
  /// (désactivé, ou fichiers sourcés suivis : leur contenu n'y figure pas).
  Future<String?> cacheKey(ScriptInfo script) async {
    if (cache == null || config.followSource) return null;
    final applicable = [
      for (final a in analyzersFor(script))
        if (config.tool(a.name).enabled) a
    ];
    final versions = await Future.wait([
      for (final a in applicable)
        (_versions[a.name] ??= a.version(runner, config))
            .then((v) => '${a.name}=$v')
    ]);
    var rules = '';
    final sg = config.tool('semgrep');
    if (script.dialect.isPython && sg.enabled && sg.config == null) {
      final f = File('${SemgrepAnalyzer.defaultCacheDir()?.path}/'
          'semgrep-${semgrepRuleset.replaceAll('/', '-')}.yaml');
      rules = f.existsSync() ? '${f.lastModifiedSync()}' : 'registre';
    }
    // Configuration Ruff du projet : ses modifications changent le rapport.
    final ruffFile = script.dialect.isPython
        ? RuffAnalyzer.ruffConfigFile(config, script.path)
        : null;
    if (ruffFile != null && File(ruffFile).existsSync()) {
      rules += '|ruff:${File(ruffFile).lastModifiedSync()}';
    }
    // Dépendances déclarées du projet (pydeps, pip-audit).
    if (script.dialect.isPython && File(script.path).existsSync()) {
      for (final f in PythonProject.find(script.path).files) {
        rules += '|${f.path}:${f.lastModifiedSync()}';
      }
    }
    final key = fastHash([
      appVersion,
      lang.name,
      script.path,
      script.dialect.name,
      script.hasCrlf,
      config.toYaml(),
      ...versions,
      rules,
      script.content,
      // Scripts intégrés : les détecteurs de secrets lisent tout le fichier.
      if (script.embedded != null) script.displayLines.join('\n'),
    ].join('\u0000'));
    return '$key-${script.content.length.toRadixString(16)}';
  }

  Future<ScriptReport> analyze(ScriptInfo script,
      {String? filePath,
      void Function(AnalysisProgress)? onProgress,
      CancelToken? cancel}) async {
    cancel?.check();
    final key = await cacheKey(script);
    final hit = key == null ? null : cache!.read(key, script);
    if (hit != null) {
      onProgress?.call(AnalysisProgress(script.path, null, 1, 1));
      return hit.withComparison(baseline?.compare(hit));
    }
    Directory? tmp;
    // Scripts intégrés : les outils reçoivent le script virtuel.
    final host = script.embedded == null ? null : filePath;
    var path = script.embedded == null ? filePath : null;
    if (path == null) {
      tmp = await Directory.systemTemp.createTemp('check_script_');
      path = '${tmp.path}/script.${script.dialect.isPython ? 'py' : 'sh'}';
      await File(path).writeAsString(script.content);
    }
    try {
      final ctx = AnalysisContext(
          script: script,
          filePath: path,
          hostPath: host,
          config: config,
          lang: lang,
          runner: runner,
          cancel: cancel);
      final applicable = analyzersFor(script);
      final total = applicable.length;
      // Les outils tournent en parallèle ; leurs résultats sont rangés dans
      // l'ordre de priorité des analyseurs (dédoublonnage inchangé).
      final results = List<AnalyzerResult?>.filled(total, null);
      final running = <String>[];
      var done = 0;
      cancel?.check();
      onProgress?.call(AnalysisProgress(script.path,
          applicable.isEmpty ? null : applicable.first.name, 0, total));
      Future<void> runOne(int i) async {
        final a = applicable[i];
        if (!config.tool(a.name).enabled) {
          results[i] = AnalyzerResult(ToolRun(a.name, ToolStatus.disabled));
          done++;
          return;
        }
        running.add(a.name);
        final r = await a.analyze(ctx);
        cancel?.check();
        final v = r.run.status == ToolStatus.ok
            ? await (_versions[a.name] ??= a.version(runner, config))
            : null;
        final run = v == null
            ? r.run
            : ToolRun(r.run.tool, r.run.status,
                version: v, detail: r.run.detail, findings: r.run.findings);
        results[i] = AnalyzerResult(run, r.findings);
        running.remove(a.name);
        done++;
        onProgress?.call(AnalysisProgress(script.path,
            running.isEmpty ? a.name : running.join(', '), done, total,
            lastRun: run));
      }

      if (parallel) {
        await Future.wait([for (var i = 0; i < total; i++) runOne(i)],
            eagerError: true);
      } else {
        for (var i = 0; i < total; i++) {
          cancel?.check();
          await runOne(i);
        }
      }
      cancel?.check();
      final runs = [for (final r in results) r!.run];
      final embedded = script.embedded;
      final raw = [
        for (final r in results)
          for (final f in r!.findings)
            if (embedded == null || !ignoredInEmbedded(f, embedded)) f
      ];

      final suppressions = Suppressions.parse(
          embedded?.directiveLines ?? script.lines,
          python: script.dialect.isPython);
      final deduped = deduplicate(raw);
      final kept = [
        for (final f in deduped)
          if (!suppressions.suppresses(f)) f,
        ...staleDirectives(suppressions, raw, runs, lang),
      ];
      final fixed = attachFixes(
          shell: !script.dialect.isPython,
          attachSource(
              fingerprintAll(
                  applyConfig(
                      escalate(enrich(kept, lang), config.contexts), config),
                  script.displayLines),
              script.displayLines,
              detected: raw),
          script.lines);
      // Pas de correction automatique dans un fichier hôte : les positions
      // du script virtuel ne sont pas toujours celles du fichier.
      final findings = sortFindings(embedded == null
          ? fixed
          : [for (final f in fixed) f.copyWith(edits: const [])]);
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
        explanation: explainScore(findings, script.codeLines, config.scoring),
      );
      onProgress?.call(AnalysisProgress(script.path, null, total, total));
      // Pas de mise en cache si un outil a échoué (réseau…) : on réessaiera.
      if (key != null && !runs.any((r) => r.status == ToolStatus.failed)) {
        await cache!.write(key, report);
      }
      return report.withComparison(baseline?.compare(report));
    } finally {
      await tmp?.delete(recursive: true);
    }
  }
}

/// Règles sans objet pour des scripts intégrés à un autre fichier : en-tête
/// et options de script (shebang, set -e…, fournis par l'hôte), mise en
/// forme, code inaccessible et variables non définies (les blocs sont
/// indépendants et l'hôte définit des variables : ENV, env:, variables:).
bool ignoredInEmbedded(Finding f, EmbeddedScript e) =>
    switch ((f.tool, f.ruleId)) {
      ('builtin', 'POR001' || 'POR002' || 'ROB001' || 'ROB003' || 'ROB014') ||
      ('builtin', 'SEC017' || 'ROB016' || 'MNT004' || 'MNT005' || 'MNT008') ||
      ('builtin', 'MNT009' || 'ROB011' || 'SEC015' || 'POR006') ||
      ('shellcheck', 'SC2148' || 'SC2317' || 'SC2154') ||
      ('shfmt', 'FORMAT') =>
        true,
      ('builtin', 'ROB002') => e.pipefail,
      _ => false,
    };

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
  final sameLine = _overlap(a, b) ||
      a.line == 0 ||
      b.line == 0 ||
      a.ruleId == 'SYNTAX' ||
      b.ruleId == 'SYNTAX';
  return sameLine && eq;
}

/// Étendue maximale (en lignes) d'une instruction prise en compte : au-delà
/// (règle couvrant une fonction entière…), seule la première ligne compte.
const maxDuplicateSpan = 6;

/// Les lignes signalées se recouvrent : même ligne, ou l'une tombe dans
/// l'instruction multi-ligne de l'autre (Bandit situe un appel sur sa
/// première ligne, Ruff sur la ligne de l'argument fautif).
bool _overlap(Finding a, Finding b) {
  if (a.line == b.line) return true;
  int end(Finding f) {
    final e = f.endLine;
    return e != null && e >= f.line && e - f.line < maxDuplicateSpan
        ? e
        : f.line;
  }

  return a.line <= end(b) && b.line <= end(a);
}

/// Conserve le premier de chaque groupe de doublons (ordre des analyseurs).
List<Finding> deduplicate(List<Finding> findings) {
  final kept = <Finding>[];
  for (final f in findings) {
    if (!kept.any((k) => isDuplicate(k, f))) kept.add(f);
  }
  return kept;
}

/// Directives `# check-script` devenues inutiles (règle MNT011). Une
/// directive n'est signalée que si l'absence de problème est certaine : ses
/// identifiants sont tous des règles intégrées, ou tous les outils ont
/// fonctionné (un outil absent ou en échec aurait pu signaler le problème).
List<Finding> staleDirectives(
    Suppressions s, List<Finding> detected, List<ToolRun> runs, Lang lang) {
  if (s.directives.isEmpty) return const [];
  final builtinRan =
      runs.any((r) => r.tool == 'builtin' && r.status == ToolStatus.ok);
  final allRan = runs.every(
      (r) => r.status == ToolStatus.ok || r.status == ToolStatus.disabled);
  final builtinIds = {for (final r in ruleCatalog) r.id};
  final info = ruleInfo('MNT011');
  return [
    for (final d in s.unused(detected))
      if (allRan || (builtinRan && d.ids.every(builtinIds.contains)))
        Finding(
          tool: 'builtin',
          ruleId: info.id,
          category: info.category,
          severity: info.severity,
          line: d.line,
          message: '${info.title.of(lang)} (${d.ids.join(', ')})',
          hint: info.fix.of(lang),
        ),
  ];
}

/// Règles signalant un secret : la ligne concernée n'est jamais recopiée
/// dans le rapport, quel que soit le problème qui la désigne.
final Set<String> _secretRules = {
  for (final r in lineRules)
    if (r.hideSnippet) r.id,
  'SEC022',
  'PYSEC001',
};

bool _revealsSecret(Finding f) => switch (f.tool) {
      'gitleaks' || 'trufflehog' => true,
      'builtin' => _secretRules.contains(f.ruleId),
      'bandit' => const {'B105', 'B106', 'B107'}.contains(f.ruleId),
      'ruff' => const {'S105', 'S106', 'S107'}.contains(f.ruleId),
      'semgrep' => semgrepSecretRule.hasMatch(f.ruleId.toLowerCase()),
      _ => false,
    };

/// Rattache à chaque problème la ligne de code qu'il désigne (sans les
/// blancs de fin). Les lignes où un secret a été détecté sont masquées pour
/// tous les problèmes qui les désignent, y compris quand le secret lui-même
/// a été écarté (directive, configuration) : [detected] liste alors tous les
/// problèmes bruts. Une correction touchant une ligne masquée est retirée :
/// son aperçu recopierait le secret.
List<Finding> attachSource(List<Finding> findings, List<String> lines,
    {List<Finding>? detected}) {
  final secretLines = {
    for (final f in detected ?? findings)
      if (_revealsSecret(f)) f.line,
  };
  bool touchesSecret(Finding f) =>
      f.edits.any((e) => secretLines.any((l) => l >= e.line && l <= e.endLine));
  return [
    for (final f in findings)
      () {
        final g = touchesSecret(f) ? f.copyWith(edits: const []) : f;
        return g.line < 1 || g.line > lines.length
            ? g
            : g.copyWith(
                snippet: () => secretLines.contains(g.line)
                    ? null
                    : lines[g.line - 1].trimRight());
      }(),
  ];
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
    ('ruff', 'FORMAT') => t(
        'Reformater avec check-script --fix (ou ruff format).',
        'Reformat with check-script --fix (or ruff format).'),
    ('vermin', _) => t(
        'Remplacer par une construction disponible dans la version cible, ou relever pythonTarget si ce Python est garanti.',
        'Replace with a construct available in the target version, or raise pythonTarget if that Python is guaranteed.'),
    ('radon', 'CC') => t(
        'Découper la fonction : extraire les branches en sous-fonctions, sortir tôt (return / continue).',
        'Split the function: extract branches into helpers, return early (return / continue).'),
    ('radon', 'MI') => t(
        'Réduire la taille et la complexité du fichier : découper en fonctions ou en modules.',
        'Reduce the file size and complexity: split into functions or modules.'),
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

/// Retire les règles désactivées (et la même règle sous le code d'un autre
/// outil) et applique les reclassements.
List<Finding> applyConfig(List<Finding> findings, CheckConfig config) => [
      for (final f in findings)
        if (!config.isRuleDisabled(f.ruleId))
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
