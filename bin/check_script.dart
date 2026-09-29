// Copyright (C) 2026 Christophe Lafaille
// SPDX-License-Identifier: LGPL-3.0-or-later

/// check-script : évalue un ou plusieurs scripts shell ou Python et produit un
/// classement (Sécurité, Robustesse, Maintenabilité, Portabilité,
/// Performance), dans le terminal et/ou dans des fichiers .md / .adoc /
/// .html / .json / .sarif ; corrige les défauts sûrs avec --fix.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:check_script/check_script.dart';
import 'package:path/path.dart' as p;

/// Codes de sortie.
const exitOk = 0;
const exitBelowThreshold = 1;
const exitUsage = 2;
const exitInput = 3;

const externalTools = [
  'shellcheck',
  'shfmt',
  'bashate',
  'checkbashisms',
  'gitleaks',
  'trufflehog',
  'syntax',
  'ruff',
  'bandit',
  'semgrep',
  'mypy',
  'pyright',
  'pylint',
  'radon',
  'vermin',
  'pydeps',
  'pip-audit',
  'hadolint',
  'actionlint',
  'zizmor',
  'commands',
  'custom',
];

ArgParser buildParser(Lang lang) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  return ArgParser()
    ..addMultiOption('output',
        abbr: 'o',
        valueHelp: 'FICHIER',
        help: t(
            'Écrit le rapport dans FICHIER (.md, .adoc, .html, .pdf, .json, .sarif, .codeclimate.json, .xml (JUnit), .txt) ; répétable.',
            'Write the report to FILE (.md, .adoc, .html, .pdf, .json, .sarif, .codeclimate.json, .xml (JUnit), .txt); repeatable.'))
    ..addOption('format',
        abbr: 'f',
        allowed: [
          'terminal',
          'md',
          'adoc',
          'html',
          'json',
          'sarif',
          'codeclimate',
          'junit',
          'github',
          'pdf',
        ],
        help: t(
            'Format de la sortie standard, et des fichiers de sortie sans '
                'extension reconnue (github : annotations GitHub Actions ; '
                'junit : JUnit XML).',
            'Format of standard output, and of output files without a known '
                'extension (github: GitHub Actions annotations; junit: JUnit '
                'XML).'))
    ..addOption('lang',
        abbr: 'l',
        allowed: ['fr', 'en'],
        help: t('Langue du rapport (défaut : selon LANG).',
            'Report language (default: from LANG).'))
    ..addOption('shell',
        abbr: 's',
        allowed: ['sh', 'bash', 'dash', 'ksh', 'zsh', 'python'],
        help: t(
            'Force le dialecte (sinon déduit du shebang, ou de l\'extension .py).',
            'Force the dialect (otherwise taken from the shebang, or the .py extension).'))
    ..addOption('python-target',
        valueHelp: 'VERSION',
        help: t(
            'Version minimale de Python à supporter (défaut : ${CheckConfig.defaultPythonTarget}).',
            'Minimum Python version to support (default: ${CheckConfig.defaultPythonTarget}).'))
    ..addOption('profile',
        abbr: 'p',
        allowed: ['strict', 'default', 'legacy'],
        help: t(
            'Profil de notation : strict (nouveaux scripts), default, legacy (existant).',
            'Scoring profile: strict (new scripts), default, legacy (existing code).'))
    ..addMultiOption('context',
        allowed: ['root', 'cron', 'systemd', 'interactive'],
        help: t('Contexte d\'exécution (durcit certaines règles) ; répétable.',
            'Execution context (hardens some rules); repeatable.'))
    ..addFlag('follow-source',
        negatable: false,
        help: t('Suit les fichiers sourcés (shellcheck -x).',
            'Follow sourced files (shellcheck -x).'))
    ..addOption('config',
        abbr: 'c',
        valueHelp: 'FICHIER',
        help: t(
            'Configuration YAML (défaut : ./.checkscript.yaml puis '
                '~/.config/check-script/config.yaml).',
            'YAML configuration (default: ./.checkscript.yaml then '
                '~/.config/check-script/config.yaml).'))
    ..addMultiOption('ref',
        valueHelp: 'RÉFÉRENCE',
        help: t(
            'N\'affiche que les problèmes rattachés à cette référence (début du nom, sans casse : CWE-78, A08, CICD-SEC, ANSSI-BP-028) ; répétable. Les notes restent celles de l\'analyse complète.',
            'Only show issues linked to this reference (name prefix, case-insensitive: CWE-78, A08, CICD-SEC, ANSSI-BP-028); repeatable. Scores stay those of the full analysis.'))
    ..addMultiOption('with',
        valueHelp: 'OUTIL',
        allowed: externalTools,
        help: t(
            'Active un outil désactivé par défaut (pylint, pyright) ; répétable.',
            'Enable a tool disabled by default (pylint, pyright); repeatable.'))
    ..addMultiOption('without',
        valueHelp: 'OUTIL',
        allowed: [...externalTools, 'builtin'],
        help: t('Désactive un outil ; répétable ou séparé par des virgules.',
            'Disable a tool; repeatable or comma-separated.'))
    ..addOption('dashboard',
        valueHelp: 'FICHIER.html',
        help: t(
            'Tableau de bord d\'équipe : un dépôt (dossier) par cible, note moyenne, évolution, règles fréquentes.',
            'Team dashboard: one repository (folder) per target, average score, trend, frequent rules.'))
    ..addOption('history-dir',
        valueHelp: 'DOSSIER',
        help: t(
            'Enregistre l\'historique des dossiers analysés dans DOSSIER (défaut avec --dashboard : ~/.local/share/check-script/history).',
            'Record the history of analysed folders in DIR (default with --dashboard: ~/.local/share/check-script/history).'))
    ..addOption('changed-since',
        valueHelp: 'REF',
        help: t(
            'N\'analyse que les scripts modifiés depuis la référence git REF (commits, modifications en cours, nouveaux fichiers).',
            'Only analyse scripts changed since git reference REF (commits, pending changes, new files).'))
    ..addFlag('cache',
        defaultsTo: true,
        help: t(
            'Réutilise les résultats d\'un script inchangé (~/.cache/check-script) ; --no-cache pour tout réanalyser.',
            'Reuse the results of an unchanged script (~/.cache/check-script); --no-cache to re-analyse everything.'))
    ..addOption('jobs',
        abbr: 'j',
        valueHelp: 'N',
        help: t(
            'Scripts analysés simultanément (défaut : selon les processeurs ; 1 : l\'un après l\'autre).',
            'Scripts analysed simultaneously (default: from the CPU count; 1: one after another).'))
    ..addFlag('no-external',
        negatable: false,
        help: t(
            'N\'utilise que les règles intégrées.', 'Use built-in rules only.'))
    ..addFlag('embedded',
        defaultsTo: true,
        help: t(
            'Dans un dossier, analyse aussi les scripts intégrés : GitHub Actions, GitLab CI, Dockerfile, Makefile, Ansible.',
            'In a folder, also analyze embedded scripts: GitHub Actions, GitLab CI, Dockerfile, Makefile, Ansible.'))
    ..addFlag('watch',
        abbr: 'w',
        negatable: false,
        help: t(
            'Réanalyse chaque script à son enregistrement (Ctrl+C pour arrêter).',
            'Re-analyse each script whenever it is saved (Ctrl+C to stop).'))
    ..addOption('baseline',
        abbr: 'b',
        valueHelp: 'RAPPORT.json',
        help: t(
            'Rapport JSON de référence : ne détaille que les nouveaux problèmes et affiche l\'évolution des notes.',
            'Baseline JSON report: only new issues are detailed and score changes are shown.'))
    ..addOption('fail-on-new',
        valueHelp: 'SÉVÉRITÉ',
        allowed: ['low', 'medium', 'high', 'critical'],
        help: t(
            'Avec --baseline : code de sortie 1 si un nouveau problème atteint cette sévérité.',
            'With --baseline: exit code 1 if a new issue reaches this severity.'))
    ..addFlag('fix',
        negatable: false,
        help: t(
            'Corrige les défauts sûrs (ShellCheck, règles intégrées, shfmt) dans le fichier.',
            'Fix safe issues (ShellCheck, built-in rules, shfmt) in place.'))
    ..addFlag('dry-run',
        negatable: false,
        help: t('Avec --fix : affiche le diff sans modifier le fichier.',
            'With --fix: show the diff without changing the file.'))
    ..addFlag('backup',
        negatable: false,
        help: t('Avec --fix : conserve l\'original en FICHIER.orig.',
            'With --fix: keep the original as FILE.orig.'))
    ..addFlag('details',
        negatable: false,
        help: t(
            'Terminal : liste tous les problèmes et leur correction (défaut : 10 par catégorie).',
            'Terminal: list every issue and its fix (default: 10 per category).'))
    ..addFlag('explain',
        negatable: false,
        help: t(
            'Terminal : coût de chaque règle sur la note, et gain en la corrigeant.',
            'Terminal: cost of each rule on the score, and gain from fixing it.'))
    ..addOption('sort',
        allowed: ['category', 'impact'],
        defaultsTo: 'category',
        help: t(
            'Terminal : problèmes par catégorie, ou par gain rapide (impact sur la note, corrections automatiques d\'abord).',
            'Terminal: issues by category, or by quick win (score impact, automatic fixes first).'))
    ..addFlag('summary',
        negatable: false,
        help: t('Terminal : synthèse seule, sans détail des problèmes.',
            'Terminal: summary only, without issue details.'))
    ..addFlag('source',
        defaultsTo: true,
        help: t(
            'Terminal : affiche la ligne de code sous chaque problème (défaut ; --no-source pour la masquer).',
            'Terminal: show the code line under each issue (default; --no-source to hide it).'))
    ..addFlag('color',
        defaultsTo: null,
        help: t(
            'Force ou désactive la couleur (défaut : auto, NO_COLOR respecté).',
            'Force or disable colour (default: auto, NO_COLOR honoured).'))
    ..addFlag('quiet',
        abbr: 'q',
        negatable: false,
        help:
            t('Pas de rapport sur la sortie standard.', 'No report on stdout.'))
    ..addMultiOption('fail-under',
        valueHelp: 'NOTE|CATÉGORIE=NOTE',
        help: t(
            'Code de sortie 1 si une note est inférieure au seuil : note globale '
                '(7) ou par catégorie (security=8,robustness=6) ; répétable.',
            'Exit code 1 if a score is below the threshold: overall (7) or per '
                'category (security=8,robustness=6); repeatable.'))
    ..addFlag('list-tools',
        negatable: false,
        help: t('Affiche les outils externes détectés.',
            'Show detected external tools.'))
    ..addFlag('list-rules',
        negatable: false,
        help: t('Affiche les règles intégrées.', 'Show built-in rules.'))
    ..addFlag('all',
        negatable: false,
        help: t(
            'Avec --list-rules : aussi les codes des outils classés par check-script.',
            'With --list-rules: also the tool codes classified by check-script.'))
    ..addFlag('version',
        abbr: 'v', negatable: false, help: t('Version.', 'Version.'))
    ..addFlag('help', abbr: 'h', negatable: false, help: t('Aide.', 'Help.'));
}

Future<void> main(List<String> argv) async {
  exitCode = await run(argv);
}

/// Seuils de `--fail-under` : clé `global` ou nom de catégorie.
/// Lève [FormatException] si une valeur est invalide.
Map<String, double> parseFailUnder(List<String> values) {
  final out = <String, double>{};
  for (final v in values) {
    for (final part in v.split(',')) {
      final item = part.trim();
      if (item.isEmpty) continue;
      final eq = item.indexOf('=');
      final key =
          eq < 0 ? 'global' : item.substring(0, eq).trim().toLowerCase();
      // La virgule sépare les seuils : décimales avec un point (6.5).
      final raw = eq < 0 ? item : item.substring(eq + 1);
      final n = double.tryParse(raw.trim());
      if (key != 'global' && Category.tryParse(key) == null) {
        throw FormatException(key);
      }
      if (n == null || n < 0 || n > 10) throw FormatException(item);
      out[key] = n;
    }
  }
  return out;
}

/// Point d'entrée testable : renvoie le code de sortie.
/// [stopWatching] : fin de la surveillance `--watch` (tests) ; sans elle,
/// la surveillance dure jusqu'à l'interruption (Ctrl+C).
Future<int> run(List<String> argv,
    {IOSink? out,
    IOSink? err,
    CommandRunner? runner,
    Future<void>? stopWatching}) async {
  out ??= stdout;
  err ??= stderr;

  // Serveur LSP pour les éditeurs : check-script lsp [--lang fr|en].
  if (argv.isNotEmpty && argv.first == 'lsp') {
    final li = argv.indexOf('--lang');
    return LspServer(stdin, stdout,
            runner: runner ?? const ProcessCommandRunner(),
            lang: li > 0 && li + 1 < argv.length
                ? Lang.tryParse(argv[li + 1])
                : null)
        .serve();
  }

  // La langue est nécessaire avant l'analyse complète des options (aide).
  var lang = Lang.fromEnvironment(Platform.environment);
  final li = argv
      .indexWhere((a) => a == '--lang' || a == '-l' || a.startsWith('--lang='));
  if (li >= 0) {
    final v = argv[li].contains('=')
        ? argv[li].split('=').last
        : (li + 1 < argv.length ? argv[li + 1] : '');
    lang = Lang.tryParse(v) ?? lang;
  }
  String t(String fr, String en) => lang == Lang.fr ? fr : en;

  final parser = buildParser(lang);
  final ArgResults a;
  try {
    a = parser.parse(argv);
  } on FormatException catch (e) {
    err.writeln(e.message);
    err.writeln(t('Voir check-script --help.', 'See check-script --help.'));
    return exitUsage;
  }

  if (a['help'] as bool) {
    out.writeln(t(
        'Usage : check-script [options] <script|dossier|->...\n\n'
            'Évalue des scripts shell ou Python sur cinq axes (Sécurité, Robustesse, '
            'Maintenabilité, Portabilité, Performance), notés sur 10.\n',
        'Usage: check-script [options] <script|directory|->...\n\n'
            'Rates shell or Python scripts on five axes (Security, Robustness, '
            'Maintainability, Portability, Performance), scored out of 10.\n'));
    out.writeln(parser.usage);
    out.writeln(t(
        '\nDirectives dans le script : # check-script disable=RÈGLE[,…] '
            '(ligne), # check-script disable-file=RÈGLE[,…] (fichier).'
            '\nCodes de sortie : 0 OK, 1 seuil non atteint (--fail-under, '
            '--fail-on-new), 2 usage/configuration, 3 script illisible.',
        '\nIn-script directives: # check-script disable=RULE[,…] (line), '
            '# check-script disable-file=RULE[,…] (file).'
            '\nExit codes: 0 OK, 1 threshold not met (--fail-under, '
            '--fail-on-new), 2 usage/configuration, 3 unreadable script.'));
    return exitOk;
  }
  if (a['version'] as bool) {
    out.writeln('check-script $appVersion');
    return exitOk;
  }

  // ── Configuration ─────────────────────────────────────────────────────────
  final profile =
      a['profile'] == null ? null : Profile.tryParse(a['profile'] as String);
  CheckConfig config;
  try {
    config = await loadConfig(a['config'] as String?, profile: profile);
  } on FormatException catch (e) {
    err.writeln(t('Configuration invalide : ${e.message}',
        'Invalid configuration: ${e.message}'));
    return exitUsage;
  } on FileSystemException catch (e) {
    err.writeln(t('Configuration illisible : ${e.path}',
        'Unreadable configuration: ${e.path}'));
    return exitUsage;
  }
  final without = [
    for (final w in a['without'] as List<String>) ...w.split(','),
    if (a['no-external'] as bool) ...externalTools,
  ];
  final ctxArgs = a['context'] as List<String>;
  final pyTarget = a['python-target'] as String?;
  if (pyTarget != null && !CheckConfig.isPythonTarget(pyTarget)) {
    err.writeln(t('--python-target : version invalide « $pyTarget » (ex. 3.9).',
        '--python-target: invalid version "$pyTarget" (e.g. 3.9).'));
    return exitUsage;
  }
  // Options de la ligne de commande, appliquées à toute configuration
  // (générale ou de projet).
  CheckConfig withCli(CheckConfig c) => c
      .withToolsEnabled(
          [for (final w in a['with'] as List<String>) ...w.split(',')])
      .withToolsDisabled(without)
      .copyWith(
        pythonTarget: pyTarget,
        contexts: ctxArgs.isEmpty
            ? null
            : {
                for (final c in ctxArgs)
                  if (c != 'interactive') ExecContext.tryParse(c)!
              },
        followSource: (a['follow-source'] as bool) ? true : null,
      );
  config = withCli(config);

  Map<String, double> failUnder;
  try {
    failUnder = parseFailUnder(a['fail-under'] as List<String>);
  } on FormatException catch (e) {
    err.writeln(t(
        '--fail-under : valeur invalide « ${e.message} » (note 0-10, ou catégorie=note).',
        '--fail-under: invalid value "${e.message}" (score 0-10, or category=score).'));
    return exitUsage;
  }

  Baseline? baseline;
  if (a['baseline'] != null) {
    try {
      baseline =
          Baseline.parse(await File(a['baseline'] as String).readAsString());
    } on FileSystemException {
      err.writeln(t('Référence illisible : ${a['baseline']}',
          'Unreadable baseline: ${a['baseline']}'));
      return exitUsage;
    } on FormatException catch (e) {
      err.writeln(e.message);
      return exitUsage;
    }
  }
  final failOnNew = a['fail-on-new'] == null
      ? null
      : Severity.tryParse(a['fail-on-new'] as String);
  if (failOnNew != null && baseline == null) {
    err.writeln(t('--fail-on-new nécessite --baseline.',
        '--fail-on-new requires --baseline.'));
    return exitUsage;
  }

  final jobsArg = a['jobs'] as String?;
  final jobs = jobsArg == null ? null : int.tryParse(jobsArg);
  if (jobsArg != null && (jobs == null || jobs < 1)) {
    err.writeln(t('--jobs : nombre entier ≥ 1 attendu.',
        '--jobs: integer ≥ 1 expected.'));
    return exitUsage;
  }

  final commandRunner = runner ?? const ProcessCommandRunner();
  // Cache seulement avec les vrais outils (pas avec un exécuteur de test).
  final cache = (a['cache'] as bool) && commandRunner is ProcessCommandRunner
      ? ResultCache.standard()
      : null;
  await cache?.prune();
  final engine = Engine(
      config: config,
      lang: lang,
      runner: commandRunner,
      baseline: baseline,
      cache: cache);

  // Configuration de projet : sans --config, chaque script prend le
  // .checkscript.yaml le plus proche (jusqu'à la racine du dépôt git) ; un
  // moteur par fichier de configuration.
  final explicitConfig = a['config'] as String?;
  final engines = <String?, Engine>{null: engine};
  Engine engineFor(String? path) {
    if (explicitConfig != null || path == null) return engine;
    final found = findProjectConfig(path);
    return engines.putIfAbsent(found, () {
      final CheckConfig c;
      try {
        c = withCli(CheckConfig.parse(File(found!).readAsStringSync(),
            profile: profile));
      } on FormatException catch (e) {
        throw _ConfigError('$found : ${e.message}');
      } on FileSystemException {
        throw _ConfigError('$found : illisible / unreadable');
      }
      return Engine(
          config: c,
          lang: lang,
          runner: commandRunner,
          baseline: baseline,
          cache: cache);
    });
  }

  if (a['list-tools'] as bool) {
    await listTools(engine, out, lang);
    return exitOk;
  }
  if (a['list-rules'] as bool) {
    // Règles personnalisées : --config, ou configuration du dossier courant.
    final CheckConfig listed;
    try {
      listed = engineFor('${Directory.current.path}/.').config;
    } on _ConfigError catch (e) {
      err.writeln(t('Configuration invalide : ${e.message}',
          'Invalid configuration: ${e.message}'));
      return exitUsage;
    }
    listRules(out, lang, all: a['all'] as bool, custom: listed.customRules);
    return exitOk;
  }

  if (a.rest.isEmpty) {
    err.writeln(t('Aucun script à analyser. Voir check-script --help.',
        'No script to analyse. See check-script --help.'));
    return exitUsage;
  }
  final fix = a['fix'] as bool;
  final dryRun = a['dry-run'] as bool;
  if ((dryRun || a['backup'] as bool) && !fix) {
    err.writeln(t('--dry-run et --backup s\'utilisent avec --fix.',
        '--dry-run and --backup are used with --fix.'));
    return exitUsage;
  }
  if (fix && !dryRun && a.rest.contains('-')) {
    err.writeln(t('--fix sur l\'entrée standard nécessite --dry-run.',
        '--fix on standard input requires --dry-run.'));
    return exitUsage;
  }
  if (a['watch'] as bool) {
    if (fix || a.rest.contains('-')) {
      err.writeln(t(
          '--watch ne s\'utilise ni avec --fix ni avec l\'entrée standard.',
          '--watch cannot be used with --fix or standard input.'));
      return exitUsage;
    }
    return _watch(argv, a, lang,
        out: out, err: err, runner: runner, stop: stopWatching);
  }

  // Fichiers modifiés depuis une référence git (--changed-since).
  final since = a['changed-since'] as String?;
  Set<String>? changed;
  if (since != null) {
    // Dépôt de la première cible (fichier ou dossier), pas du dossier
    // courant : la commande marche depuis n'importe où.
    final first = a.rest.firstWhere((x) => x != '-', orElse: () => '.');
    final gitDir =
        FileSystemEntity.isDirectorySync(first) ? first : p.dirname(first);
    final r = await changedSince(since, dir: gitDir, runner: commandRunner);
    if (r.files == null) {
      err.writeln('--changed-since : ${r.error}');
      return exitUsage;
    }
    changed = r.files;
  }
  var skippedUnchanged = 0;

  // ── Analyse (et correction) ───────────────────────────────────────────────
  final dialect =
      a['shell'] == null ? null : Dialect.tryParse(a['shell'] as String);
  final reports = <ScriptReport>[];
  var inputError = false;

  // Les closures ne profitent pas de la promotion de type de out/err.
  final IOSink outSink = out, errSink = err;
  Future<void> handle(ScriptInfo script, String? path) async {
    final eng = engineFor(path);
    if (fix) {
      final r =
          await fixScript(script, config: eng.config, runner: commandRunner);
      final name = path ?? '<stdin>';
      if (r.aborted != null) {
        errSink.writeln(t(
            '$name : corrections abandonnées (la syntaxe ne serait plus valide) : ${r.aborted}',
            '$name: fixes dropped (the syntax would become invalid): ${r.aborted}'));
      } else if (!r.changed) {
        errSink.writeln(t('$name : aucune correction automatique applicable.',
            '$name: no automatic fix applicable.'));
      } else {
        final summary =
            r.applied.entries.map((e) => '${e.key} ×${e.value}').join(', ');
        if (dryRun) {
          outSink.write(unifiedDiff(r.original, r.fixed,
              fromName: '$name.orig', toName: name));
          errSink.writeln(t('$name : corrections possibles : $summary',
              '$name: available fixes: $summary'));
        } else {
          if (a['backup'] as bool) {
            await File('$path.orig').writeAsString(r.original);
          }
          await File(path!).writeAsString(r.fixed);
          errSink.writeln(
              t('$name : corrigé ($summary)', '$name: fixed ($summary)'));
          script =
              ScriptInfo.fromContent(path, r.fixed, forcedDialect: dialect);
        }
      }
    }
    reports.add(await eng.analyze(script, filePath: dryRun ? null : path));
  }

  // Une configuration de projet invalide arrête l'analyse (code 2).
  try {
    for (final target in a.rest) {
      if (target == '-') {
        final content = await _readStdin();
        await handle(
            ScriptInfo.fromContent('<stdin>', content, forcedDialect: dialect),
            null);
        continue;
      }
      var files = await collectScripts(target, embedded: a['embedded'] as bool);
      if (files != null && changed != null) {
        final all = files.length;
        files = [
          for (final f in files)
            if (changed.contains(normalizedPath(f))) f
        ];
        skippedUnchanged += all - files.length;
        if (files.isEmpty) continue;
      }
      if (files == null) {
        err.writeln(t('Introuvable : $target', 'Not found: $target'));
        inputError = true;
        continue;
      }
      if (files.isEmpty) {
        err.writeln(t('Aucun script shell ou Python dans : $target',
            'No shell or Python script in: $target'));
      }
      // Sans correction ni dialecte forcé, les scripts d'un dossier sont
      // analysés en parallèle (ordre des rapports conservé).
      if (!fix && dialect == null && jobs != 1) {
        // Regroupés par configuration de projet, puis remis dans l'ordre.
        final byEngine = <Engine, List<String>>{};
        for (final f in files) {
          (byEngine[engineFor(f)] ??= []).add(f);
        }
        final done = <String, ScriptReport>{};
        for (final e in byEngine.entries) {
          for (final r in await e.key.analyzeFiles(e.value, jobs: jobs,
              onSkip: (f, err) {
            errSink.writeln(err is FormatException
                ? t('Fichier non textuel ignoré : $f',
                    'Non-text file skipped: $f')
                : t('Lecture impossible : $f', 'Cannot read: $f'));
            inputError = true;
          })) {
            done[r.script.path] = r;
          }
        }
        reports.addAll([
          for (final f in files)
            if (done[f] != null) done[f]!
        ]);
        continue;
      }
      for (final f in files) {
        try {
          final content = await File(f).readAsString();
          await handle(
              ScriptInfo.fromContent(f, content, forcedDialect: dialect), f);
        } on FileSystemException catch (e) {
          err.writeln(t(
              'Lecture impossible : $f (${e.osError?.message ?? e.message})',
              'Cannot read: $f (${e.osError?.message ?? e.message})'));
          inputError = true;
        } on FormatException {
          err.writeln(t(
              'Fichier non textuel ignoré : $f', 'Non-text file skipped: $f'));
          inputError = true;
        }
      }
    }
  } on _ConfigError catch (e) {
    err.writeln(t('Configuration invalide : ${e.message}',
        'Invalid configuration: ${e.message}'));
    return exitUsage;
  }
  // Historique des dossiers analysés, tableau de bord d'équipe.
  final dashboard = a['dashboard'] as String?;
  final historyDir = a['history-dir'] as String?;
  if (dashboard != null || historyDir != null) {
    final history = historyDir != null
        ? FolderHistory(Directory(historyDir))
        : FolderHistory.standard();
    final repos = <DashboardRepo>[];
    for (final target in a.rest) {
      if (target == '-' || !FileSystemEntity.isDirectorySync(target)) continue;
      final root = p.absolute(target);
      final reps = [
        for (final r in reports)
          if (p.isWithin(root, p.absolute(r.script.path))) r
      ];
      if (reps.isEmpty) continue;
      final entries =
          await history?.append(target, HistoryEntry.of(target, reps)) ??
              [HistoryEntry.of(target, reps)];
      repos.add(
          DashboardRepo(p.basename(p.normalize(root)), target, reps, entries));
    }
    if (dashboard != null) {
      try {
        final f = File(dashboard);
        await f.parent.create(recursive: true);
        await f.writeAsString(renderDashboard(repos, lang));
        err.writeln(Messages(lang).reportWritten(dashboard));
      } on FileSystemException catch (e) {
        err.writeln(t('Écriture impossible : $dashboard (${e.message})',
            'Cannot write: $dashboard (${e.message})'));
        return exitInput;
      }
    }
  }

  if (reports.isEmpty && changed != null && !inputError) {
    err.writeln(t(
        'Aucun script modifié depuis $since ($skippedUnchanged inchangé${skippedUnchanged > 1 ? 's' : ''}).',
        'No script changed since $since ($skippedUnchanged unchanged).'));
    return exitOk;
  }
  if (reports.isEmpty) return inputError ? exitInput : exitUsage;
  final refFilter = a['ref'] as List<String>;
  if (refFilter.isNotEmpty) {
    for (var i = 0; i < reports.length; i++) {
      reports[i] = reports[i].withFindings([
        for (final f in reports[i].findings)
          if (matchesReference(f.refs, refFilter)) f
      ]);
    }
  }
  if (baseline != null) {
    for (final r in reports.where((r) => r.comparison == null)) {
      err.writeln('${r.script.path} : ${Messages(lang).notInBaseline}');
    }
  }

  // ── Sorties ───────────────────────────────────────────────────────────────
  final forced =
      a['format'] == null ? null : OutputFormat.tryParse(a['format'] as String);
  final outputs = a['output'] as List<String>;
  final colorFlag = a['color'] as bool?;
  final color = colorFlag ??
      (stdout.hasTerminal &&
          identical(out, stdout) &&
          !Platform.environment.containsKey('NO_COLOR'));
  final maxDetails =
      (a['summary'] as bool) ? 0 : ((a['details'] as bool) ? null : 10);

  // En --dry-run, la sortie standard porte le diff.
  if (!(a['quiet'] as bool) && !dryRun) {
    final fmt = forced ?? OutputFormat.terminal;
    out.add(await renderBytes(
        reports,
        fmt,
        RenderOptions(
            lang: lang,
            color: color && fmt == OutputFormat.terminal,
            maxDetails: maxDetails,
            showSource: a['source'] as bool,
            explain: a['explain'] as bool,
            byQuickWin: a['sort'] == 'impact')));
  }
  for (final path in outputs) {
    // L'extension prime ; --format sert aux fichiers sans extension connue.
    final fmt = OutputFormat.fromPath(path) ?? forced ?? OutputFormat.markdown;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
          await renderBytes(reports, fmt, RenderOptions(lang: lang)));
      err.writeln(Messages(lang).reportWritten(path));
    } on FileSystemException catch (e) {
      err.writeln(t(
          'Écriture impossible : $path (${e.osError?.message ?? e.message})',
          'Cannot write: $path (${e.osError?.message ?? e.message})'));
      return exitInput;
    }
  }

  if (inputError) return exitInput;
  if (failsThresholds(reports, failUnder, failOnNew)) return exitBelowThreshold;
  return exitOk;
}

/// `--watch` : une première analyse, puis une nouvelle à chaque
/// enregistrement d'un script — les scripts modifiés seulement, ou toutes
/// les cibles quand des fichiers de rapport (-o) sont écrits.
Future<int> _watch(List<String> argv, ArgResults a, Lang lang,
    {required IOSink out,
    required IOSink err,
    CommandRunner? runner,
    Future<void>? stop}) async {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  final once = [
    for (final x in argv)
      if (x != '--watch') x
  ];
  final options = List.of(once);
  for (final target in a.rest) {
    options.removeAt(options.lastIndexOf(target));
  }
  final full = (a['output'] as List<String>).isNotEmpty;
  final embedded = a['embedded'] as bool;
  var code = await run(once, out: out, err: err, runner: runner);
  void waiting() => err.writeln(t(
      '\nSurveillance de ${a.rest.join(', ')} (Ctrl+C pour arrêter)…',
      '\nWatching ${a.rest.join(', ')} (Ctrl+C to stop)…'));
  waiting();
  final explicit = {
    for (final x in a.rest)
      if (FileSystemEntity.isFileSync(x)) p.normalize(p.absolute(x)),
  };
  final done = Completer<void>();
  late final StreamSubscription<Set<String>> sub;
  sub = watchTargets(a.rest, embedded: embedded).listen((changed) async {
    sub.pause();
    try {
      final scripts = [
        for (final f in changed.toList()..sort())
          if (explicit.contains(f) ||
              (File(f).existsSync() &&
                  await isScriptFile(f, embedded: embedded)))
            f
      ];
      if (scripts.isEmpty) return;
      final now = DateTime.now().toIso8601String().substring(11, 19);
      out.writeln(
          '\n── $now — ${scripts.map((f) => p.relative(f)).join(', ')} ──');
      code = await run([...options, ...(full ? a.rest : scripts)],
          out: out, err: err, runner: runner);
      waiting();
    } finally {
      sub.resume();
    }
  });
  stop?.then((_) {
    if (!done.isCompleted) done.complete();
  });
  await done.future;
  await sub.cancel();
  return code;
}

/// Vrai si un rapport passe sous un seuil `--fail-under` ou contient un
/// nouveau problème de sévérité ≥ [failOnNew].
bool failsThresholds(List<ScriptReport> reports, Map<String, double> failUnder,
    Severity? failOnNew) {
  for (final r in reports) {
    for (final e in failUnder.entries) {
      final v = e.key == 'global'
          ? r.global
          : r.score(Category.tryParse(e.key)!).score;
      if (v < e.value) return true;
    }
    if (failOnNew != null &&
        (r.comparison?.added.any((f) => f.severity.index <= failOnNew.index) ??
            false)) {
      return true;
    }
  }
  return false;
}

Future<String> _readStdin() async {
  final chunks = <int>[];
  await for (final c in stdin) {
    chunks.addAll(c);
  }
  return systemEncoding.decode(chunks);
}

/// Charge la configuration : fichier explicite, sinon `./.checkscript.yaml`,
/// sinon `$XDG_CONFIG_HOME/check-script/config.yaml`, sinon défauts du profil.
Future<CheckConfig> loadConfig(String? explicit, {Profile? profile}) async {
  if (explicit != null) {
    return CheckConfig.parse(await File(explicit).readAsString(),
        profile: profile);
  }
  final env = Platform.environment;
  final xdg = env['XDG_CONFIG_HOME'] ??
      (env['HOME'] == null ? null : p.join(env['HOME']!, '.config'));
  for (final c in [
    '.checkscript.yaml',
    if (xdg != null) p.join(xdg, 'check-script', 'config.yaml'),
  ]) {
    final f = File(c);
    if (await f.exists()) {
      return CheckConfig.parse(await f.readAsString(), profile: profile);
    }
  }
  return CheckConfig.forProfile(profile ?? Profile.standard);
}

Future<void> listTools(Engine engine, IOSink out, Lang lang) async {
  final t = Messages(lang);
  final builtIn = lang == Lang.fr ? 'intégré' : 'built in';
  out.writeln('${t.tool.padRight(16)}${t.language_.padRight(10)}'
      '${t.status.padRight(20)}${t.version}');
  for (final an in engine.analyzers) {
    final tc = engine.config.tool(an.name);
    final head = '${an.name.padRight(16)}'
        '${t.toolLanguage(an.language).padRight(10)}';
    if (an.name == 'builtin') {
      final rules = allBuiltinRules();
      final py = rules.where((r) => r.python).length;
      out.writeln('$head${builtIn.padRight(20)}'
          '${rules.length - py} + $py ${lang == Lang.fr ? 'règles' : 'rules'}');
      continue;
    }
    if (!tc.enabled) {
      out.writeln('$head${t.toolStatus(ToolStatus.disabled)}');
      continue;
    }
    if (an.name == 'custom') {
      final n = engine.config.customRules.length;
      out.writeln('$head${builtIn.padRight(20)}'
          '$n ${lang == Lang.fr ? 'règle(s) personnalisée(s)' : 'custom rule(s)'}');
      continue;
    }
    if (an.name == 'syntax') {
      out.writeln('$head${builtIn.padRight(20)}'
          'bash -n / sh -n / $pythonExecutable compile()');
      continue;
    }
    final v = await an.version(engine.runner, engine.config);
    out.writeln('$head'
        '${(v == null ? t.toolStatus(ToolStatus.missing) : (lang == Lang.fr ? 'disponible' : 'available')).padRight(20)}'
        '${v ?? _installHint(an.name, lang)}');
  }
}

String _installHint(String tool, Lang lang) {
  final how = switch (tool) {
    'shellcheck' => 'dnf install ShellCheck | apt install shellcheck',
    'shfmt' => 'dnf install shfmt | apt install shfmt',
    'bashate' => 'pip install --user bashate',
    'checkbashisms' =>
      'dnf install devscripts-checkbashisms | apt install devscripts',
    'gitleaks' => 'https://github.com/gitleaks/gitleaks/releases',
    'trufflehog' => 'https://github.com/trufflesecurity/trufflehog/releases',
    'ruff' ||
    'bandit' ||
    'semgrep' ||
    'mypy' ||
    'pylint' ||
    'radon' ||
    'vermin' ||
    'pip-audit' =>
      'pipx install $tool',
    'pyright' => 'pipx install pyright | npm install -g pyright',
    'hadolint' => 'https://github.com/hadolint/hadolint/releases',
    'actionlint' => 'https://github.com/rhysd/actionlint/releases',
    'zizmor' => 'pipx install zizmor',
    _ => '',
  };
  return how.isEmpty
      ? ''
      : '(${lang == Lang.fr ? 'installer' : 'install'} : $how)';
}

void listRules(IOSink out, Lang lang,
    {bool all = false, List<CustomRule> custom = const []}) {
  final t = Messages(lang);
  if (all) {
    // Registre complet : règles intégrées et codes externes classés.
    for (final e in [...knownRules(lang), ...customRuleEntries(custom, lang)]) {
      out.writeln('${e.id.padRight(16)}${e.tool.padRight(15)}'
          '${t.toolLanguage(e.language).padRight(8)}'
          '${t.category(e.category).padRight(17)}'
          '${(e.severity?.label ?? '—').padRight(10)}${e.title}');
    }
    return;
  }
  for (final r in allBuiltinRules()) {
    final ctx = r.contexts.isEmpty
        ? ''
        : ' [${r.contexts.map((c) => c.name).join(', ')}]';
    out.writeln(
        '${r.id.padRight(9)}${(r.python ? 'python' : 'shell').padRight(8)}'
        '${t.category(r.category).padRight(17)}'
        '${r.severity.label.padRight(10)}${r.title.of(lang)}$ctx');
    final refs = referencesOf(r.id);
    if (refs.isNotEmpty) out.writeln('${' ' * 44}${refs.join(' · ')}');
  }
  for (final r in custom) {
    out.writeln('${r.id.padRight(9)}${'custom'.padRight(8)}'
        '${t.category(r.category).padRight(17)}'
        '${r.severity.label.padRight(10)}${r.message.of(lang)}');
  }
}

/// Configuration de projet invalide rencontrée pendant l'analyse.
class _ConfigError implements Exception {
  const _ConfigError(this.message);
  final String message;
}
