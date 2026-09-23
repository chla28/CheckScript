/// check-script : évalue un ou plusieurs scripts shell et produit un
/// classement (Sécurité, Robustesse, Maintenabilité, Portabilité,
/// Performance), dans le terminal et/ou dans des fichiers .md / .adoc /
/// .html / .json / .sarif ; corrige les défauts sûrs avec --fix.
library;

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
];

ArgParser buildParser(Lang lang) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  return ArgParser()
    ..addMultiOption('output',
        abbr: 'o',
        valueHelp: 'FICHIER',
        help: t(
            'Écrit le rapport dans FICHIER (.md, .adoc, .html, .json, .sarif, .codeclimate.json, .txt) ; répétable.',
            'Write the report to FILE (.md, .adoc, .html, .json, .sarif, .codeclimate.json, .txt); repeatable.'))
    ..addOption('format',
        abbr: 'f',
        allowed: [
          'terminal',
          'md',
          'adoc',
          'html',
          'json',
          'sarif',
          'codeclimate'
        ],
        help: t(
            'Format des fichiers de sortie sans extension reconnue, ou de la '
                'sortie standard si aucun -o.',
            'Format of output files without a known extension, or of stdout '
                'when no -o is given.'))
    ..addOption('lang',
        abbr: 'l',
        allowed: ['fr', 'en'],
        help: t('Langue du rapport (défaut : selon LANG).',
            'Report language (default: from LANG).'))
    ..addOption('shell',
        abbr: 's',
        allowed: ['sh', 'bash', 'dash', 'ksh', 'zsh'],
        help: t('Force le dialecte (sinon déduit du shebang).',
            'Force the dialect (otherwise taken from the shebang).'))
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
    ..addMultiOption('without',
        valueHelp: 'OUTIL',
        allowed: [...externalTools, 'builtin'],
        help: t('Désactive un outil ; répétable ou séparé par des virgules.',
            'Disable a tool; repeatable or comma-separated.'))
    ..addFlag('no-external',
        negatable: false,
        help: t(
            'N\'utilise que les règles intégrées.', 'Use built-in rules only.'))
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
    ..addFlag('summary',
        negatable: false,
        help: t('Terminal : synthèse seule, sans détail des problèmes.',
            'Terminal: summary only, without issue details.'))
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
Future<int> run(List<String> argv,
    {IOSink? out, IOSink? err, CommandRunner? runner}) async {
  out ??= stdout;
  err ??= stderr;

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
            'Évalue des scripts shell sur cinq axes (Sécurité, Robustesse, '
            'Maintenabilité, Portabilité, Performance), notés sur 10.\n',
        'Usage: check-script [options] <script|directory|->...\n\n'
            'Rates shell scripts on five axes (Security, Robustness, '
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
  config = config.withToolsDisabled(without).copyWith(
        contexts: ctxArgs.isEmpty
            ? null
            : {
                for (final c in ctxArgs)
                  if (c != 'interactive') ExecContext.tryParse(c)!
              },
        followSource: (a['follow-source'] as bool) ? true : null,
      );

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

  final commandRunner = runner ?? const ProcessCommandRunner();
  final engine = Engine(
      config: config, lang: lang, runner: commandRunner, baseline: baseline);

  if (a['list-tools'] as bool) {
    await listTools(engine, out, lang);
    return exitOk;
  }
  if (a['list-rules'] as bool) {
    listRules(out, lang);
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

  // ── Analyse (et correction) ───────────────────────────────────────────────
  final dialect =
      a['shell'] == null ? null : Dialect.tryParse(a['shell'] as String);
  final reports = <ScriptReport>[];
  var inputError = false;

  // Les closures ne profitent pas de la promotion de type de out/err.
  final IOSink outSink = out, errSink = err;
  Future<void> handle(ScriptInfo script, String? path) async {
    if (fix) {
      final r = await fixScript(script, config: config, runner: commandRunner);
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
    reports.add(await engine.analyze(script, filePath: dryRun ? null : path));
  }

  for (final target in a.rest) {
    if (target == '-') {
      final content = await _readStdin();
      await handle(
          ScriptInfo.fromContent('<stdin>', content, forcedDialect: dialect),
          null);
      continue;
    }
    final files = await collectScripts(target);
    if (files == null) {
      err.writeln(t('Introuvable : $target', 'Not found: $target'));
      inputError = true;
      continue;
    }
    if (files.isEmpty) {
      err.writeln(t(
          'Aucun script shell dans : $target', 'No shell script in: $target'));
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
        err.writeln(
            t('Fichier non textuel ignoré : $f', 'Non-text file skipped: $f'));
        inputError = true;
      }
    }
  }
  if (reports.isEmpty) return inputError ? exitInput : exitUsage;
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
    final fmt = outputs.isEmpty
        ? (forced ?? OutputFormat.terminal)
        : OutputFormat.terminal;
    out.write(render(
        reports,
        fmt,
        RenderOptions(
            lang: lang,
            color: color && fmt == OutputFormat.terminal,
            maxDetails: maxDetails)));
  }
  for (final path in outputs) {
    final fmt = forced ?? OutputFormat.fromPath(path) ?? OutputFormat.markdown;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(render(reports, fmt, RenderOptions(lang: lang)));
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

final _shellShebang = RegExp(r'^#!.*\b(?:ba|da|k|mk|z)?sh\b');
const _shellExt = {'.sh', '.bash', '.ksh', '.dash', '.zsh'};

/// Fichier → [fichier] ; dossier → scripts shell qu'il contient (extension ou
/// shebang), récursivement, dossiers cachés exclus ; null si introuvable.
Future<List<String>?> collectScripts(String target) async {
  final type = await FileSystemEntity.type(target);
  if (type == FileSystemEntityType.file) return [target];
  if (type != FileSystemEntityType.directory) return null;
  final found = <String>[];
  await for (final e
      in Directory(target).list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: target);
    if (p.split(rel).any((s) => s.startsWith('.'))) continue;
    if (_shellExt.contains(p.extension(e.path).toLowerCase())) {
      found.add(e.path);
      continue;
    }
    if (p.extension(e.path).isNotEmpty) continue;
    try {
      final head = await e.openRead(0, 128).first;
      if (_shellShebang
          .hasMatch(String.fromCharCodes(head).split('\n').first)) {
        found.add(e.path);
      }
    } on Object {
      // Fichier illisible ou vide : ignoré.
    }
  }
  found.sort();
  return found;
}

Future<void> listTools(Engine engine, IOSink out, Lang lang) async {
  final t = Messages(lang);
  out.writeln('${t.tool.padRight(16)}${t.status.padRight(20)}${t.version}');
  for (final an in engine.analyzers) {
    final tc = engine.config.tool(an.name);
    if (an.name == 'builtin') {
      out.writeln(
          '${'builtin'.padRight(16)}${(lang == Lang.fr ? 'intégré' : 'built in').padRight(20)}'
          '${allBuiltinRules().length} ${lang == Lang.fr ? 'règles' : 'rules'}');
      continue;
    }
    if (!tc.enabled) {
      out.writeln(
          '${an.name.padRight(16)}${t.toolStatus(ToolStatus.disabled)}');
      continue;
    }
    if (an.name == 'syntax') {
      out.writeln(
          '${'syntax'.padRight(16)}${(lang == Lang.fr ? 'intégré' : 'built in').padRight(20)}'
          'bash -n / sh -n');
      continue;
    }
    final v = await an.version(engine.runner, engine.config);
    out.writeln('${an.name.padRight(16)}'
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
    _ => '',
  };
  return how.isEmpty
      ? ''
      : '(${lang == Lang.fr ? 'installer' : 'install'} : $how)';
}

void listRules(IOSink out, Lang lang) {
  final t = Messages(lang);
  for (final r in allBuiltinRules()) {
    final ctx = r.contexts.isEmpty
        ? ''
        : ' [${r.contexts.map((c) => c.name).join(', ')}]';
    out.writeln('${r.id.padRight(9)}${t.category(r.category).padRight(17)}'
        '${r.severity.label.padRight(10)}${r.title.of(lang)}$ctx');
  }
}
