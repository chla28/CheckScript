/// check-script : évalue un ou plusieurs scripts shell et produit un
/// classement (Sécurité, Robustesse, Maintenabilité, Portabilité,
/// Performance), dans le terminal et/ou dans des fichiers .md / .adoc / .json.
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
  'syntax'
];

ArgParser buildParser(Lang lang) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  return ArgParser()
    ..addMultiOption('output',
        abbr: 'o',
        valueHelp: 'FICHIER',
        help: t(
            'Écrit le rapport dans FICHIER (.md, .adoc, .json, .txt) ; répétable.',
            'Write the report to FILE (.md, .adoc, .json, .txt); repeatable.'))
    ..addOption('format',
        abbr: 'f',
        allowed: ['terminal', 'md', 'adoc', 'json'],
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
    ..addFlag('details',
        negatable: false,
        help: t(
            'Terminal : liste tous les problèmes (défaut : 10 par catégorie).',
            'Terminal: list every issue (default: 10 per category).'))
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
    ..addOption('fail-under',
        valueHelp: 'NOTE',
        help: t(
            'Code de sortie 1 si une note globale est inférieure à NOTE (0-10).',
            'Exit code 1 if an overall score is below SCORE (0-10).'))
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
        '\nCodes de sortie : 0 OK, 1 note sous --fail-under, 2 usage/configuration, '
            '3 script illisible.',
        '\nExit codes: 0 OK, 1 score below --fail-under, 2 usage/configuration, '
            '3 unreadable script.'));
    return exitOk;
  }
  if (a['version'] as bool) {
    out.writeln('check-script $appVersion');
    return exitOk;
  }

  // ── Configuration ─────────────────────────────────────────────────────────
  CheckConfig config;
  try {
    config = await loadConfig(a['config'] as String?);
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
  config = config.withToolsDisabled(without);

  final engine = Engine(
      config: config,
      lang: lang,
      runner: runner ?? const ProcessCommandRunner());

  if (a['list-tools'] as bool) {
    await listTools(engine, out, lang);
    return exitOk;
  }
  if (a['list-rules'] as bool) {
    listRules(out, lang);
    return exitOk;
  }

  double? failUnder;
  if (a['fail-under'] != null) {
    failUnder =
        double.tryParse((a['fail-under'] as String).replaceAll(',', '.'));
    if (failUnder == null || failUnder < 0 || failUnder > 10) {
      err.writeln(t('--fail-under : note entre 0 et 10 attendue.',
          '--fail-under: a score between 0 and 10 is expected.'));
      return exitUsage;
    }
  }

  if (a.rest.isEmpty) {
    err.writeln(t('Aucun script à analyser. Voir check-script --help.',
        'No script to analyse. See check-script --help.'));
    return exitUsage;
  }

  // ── Analyse ───────────────────────────────────────────────────────────────
  final dialect =
      a['shell'] == null ? null : Dialect.tryParse(a['shell'] as String);
  final reports = <ScriptReport>[];
  var inputError = false;
  for (final target in a.rest) {
    if (target == '-') {
      final content = await _readStdin();
      reports.add(await engine.analyze(
          ScriptInfo.fromContent('<stdin>', content, forcedDialect: dialect)));
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
        reports.add(await engine.analyzeFile(f, dialect: dialect));
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

  if (!(a['quiet'] as bool)) {
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
  if (failUnder != null && reports.any((r) => r.global < failUnder!)) {
    return exitBelowThreshold;
  }
  return exitOk;
}

Future<String> _readStdin() async {
  final chunks = <int>[];
  await for (final c in stdin) {
    chunks.addAll(c);
  }
  return systemEncoding.decode(chunks);
}

/// Charge la configuration : fichier explicite, sinon `./.checkscript.yaml`,
/// sinon `$XDG_CONFIG_HOME/check-script/config.yaml`, sinon défauts.
Future<CheckConfig> loadConfig(String? explicit) async {
  if (explicit != null) {
    return CheckConfig.parse(await File(explicit).readAsString());
  }
  final env = Platform.environment;
  final xdg = env['XDG_CONFIG_HOME'] ??
      (env['HOME'] == null ? null : p.join(env['HOME']!, '.config'));
  for (final c in [
    '.checkscript.yaml',
    if (xdg != null) p.join(xdg, 'check-script', 'config.yaml'),
  ]) {
    final f = File(c);
    if (await f.exists()) return CheckConfig.parse(await f.readAsString());
  }
  return const CheckConfig();
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
    _ => '',
  };
  return how.isEmpty
      ? ''
      : '(${lang == Lang.fr ? 'installer' : 'install'} : $how)';
}

void listRules(IOSink out, Lang lang) {
  final t = Messages(lang);
  for (final r in allBuiltinRules()) {
    out.writeln('${r.id.padRight(9)}${t.category(r.category).padRight(17)}'
        '${r.severity.label.padRight(10)}${r.title.of(lang)}');
  }
}
