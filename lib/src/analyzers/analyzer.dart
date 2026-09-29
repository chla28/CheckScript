/// Contrat commun des analyseurs et abstraction de l'exécution de commandes.
library;

import 'dart:async';
import 'dart:io';

import '../config.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../script_info.dart';

/// Résultat brut d'une commande externe.
class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const CommandResult(this.exitCode, this.stdout, this.stderr);
}

/// Jeton d'annulation d'une analyse (interface graphique, Ctrl+C…).
class CancelToken {
  var _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// Enregistre une action exécutée à l'annulation (immédiatement si elle a
  /// déjà eu lieu) ; renvoie une fonction de désinscription.
  void Function() onCancel(void Function() action) {
    if (_cancelled) {
      action();
      return () {};
    }
    _listeners.add(action);
    return () => _listeners.remove(action);
  }

  /// Lève [AnalysisCancelled] si l'analyse a été annulée.
  void check() {
    if (_cancelled) throw const AnalysisCancelled();
  }
}

class AnalysisCancelled implements Exception {
  const AnalysisCancelled();
  @override
  String toString() => 'Analyse annulée';
}

/// Exécute les outils externes. Remplacé par un faux dans les tests.
abstract class CommandRunner {
  /// Exécute [executable] (avec [stdin] sur l'entrée standard si fourni) ;
  /// renvoie null si l'exécutable est introuvable. Le processus est tué si
  /// [cancel] est déclenché.
  Future<CommandResult?> run(String executable, List<String> args,
      {String? stdin, CancelToken? cancel});
}

/// L'outil s'exécute dans un Flatpak (variable `FLATPAK_ID`).
bool get inFlatpak => Platform.environment.containsKey('FLATPAK_ID');

/// Commande qui lance [executable] sur l'hôte depuis un Flatpak : les
/// outils d'analyse (ShellCheck, Ruff, bash…) sont ceux du système, pas ceux
/// du bac à sable. [env] est transmis explicitement (flatpak-spawn ne
/// propage pas l'environnement).
(String, List<String>) hostInvocation(String executable, List<String> args,
        {Map<String, String> env = const {}}) =>
    (
      'flatpak-spawn',
      [
        '--host',
        for (final e in env.entries) '--env=${e.key}=${e.value}',
        executable,
        ...args,
      ]
    );

class ProcessCommandRunner implements CommandRunner {
  /// [onHost] : lancer les outils sur l'hôte (flatpak-spawn) ; null :
  /// automatiquement dans un Flatpak.
  const ProcessCommandRunner({this.onHost});

  final bool? onHost;

  /// Chemin absolu des exécutables sur l'hôte (null : absent), résolu une
  /// fois chacun : le portail Flatpak cherche l'exécutable avec son propre
  /// PATH minimal, pas celui passé par --env.
  static final _onHostPath = <String, Future<String?>>{};

  /// PATH de l'utilisateur sur l'hôte : flatpak-spawn ne donne qu'un PATH
  /// minimal, sans ~/.local/bin ni ~/bin (où pip, pipx… installent Ruff,
  /// Bandit…). Lu une fois par un shell de connexion.
  static Future<String>? _hostPath;

  static Future<String> _readHostPath() async {
    final home = Platform.environment['HOME'] ?? '';
    final fallback = [
      '$home/.local/bin',
      '$home/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/usr/local/sbin',
      '/usr/sbin',
      '/sbin',
    ].join(':');
    try {
      final r = await Process.run(
          'flatpak-spawn', ['--host', 'bash', '-lc', 'printf %s "\$PATH"']);
      final path = '${r.stdout}'.trim();
      return r.exitCode == 0 && path.isNotEmpty ? '$path:$fallback' : fallback;
    } on ProcessException {
      return fallback;
    }
  }

  static Future<String?> _hostResolve(String executable, String path) async {
    try {
      final r = await Process.run('flatpak-spawn', [
        '--host',
        '--env=PATH=$path',
        'sh',
        '-c',
        'command -v "\$1"',
        'sh',
        executable,
      ]);
      final found = '${r.stdout}'.trim().split('\n').first;
      return r.exitCode == 0 && found.startsWith('/') ? found : null;
    } on ProcessException {
      return null;
    }
  }

  @override
  Future<CommandResult?> run(String executable, List<String> args,
      {String? stdin, CancelToken? cancel}) async {
    // LC_ALL=C : messages des outils (bash -n…) en anglais, donc analysables.
    const env = {'LC_ALL': 'C'};
    var exe = executable;
    var argv = args;
    if (onHost ?? inFlatpak) {
      final path = await (_hostPath ??= _readHostPath());
      // Un outil absent de l'hôte reste « absent » (flatpak-spawn existe).
      final resolved =
          await (_onHostPath[executable] ??= _hostResolve(executable, path));
      if (resolved == null) return null;
      (exe, argv) = hostInvocation(resolved, args, env: {...env, 'PATH': path});
    }
    final Process p;
    try {
      p = await Process.start(exe, argv, environment: env);
    } on ProcessException {
      return null;
    }
    final unregister = cancel?.onCancel(() => p.kill()) ?? () {};
    try {
      final out = p.stdout.transform(systemEncoding.decoder).join();
      final err = p.stderr.transform(systemEncoding.decoder).join();
      if (stdin != null) p.stdin.write(stdin);
      await p.stdin.close().catchError((_) {});
      final code = await p.exitCode;
      final result = CommandResult(code, await out, await err);
      cancel?.check();
      return result;
    } finally {
      unregister();
    }
  }
}

/// Tout ce dont un analyseur a besoin pour traiter un script.
class AnalysisContext {
  final ScriptInfo script;

  /// Chemin d'un fichier contenant le script, lisible par les outils externes
  /// (copie temporaire si le script provient de l'entrée standard).
  final String filePath;
  final CheckConfig config;
  final Lang lang;
  final CommandRunner runner;
  final CancelToken? cancel;

  /// Fichier hôte des scripts intégrés (Dockerfile, CI…) : les détecteurs
  /// de secrets le parcourent en entier (null : [filePath]).
  final String? hostPath;

  const AnalysisContext({
    required this.script,
    required this.filePath,
    this.hostPath,
    required this.config,
    required this.lang,
    required this.runner,
    this.cancel,
  });

  /// Fichier à parcourir pour y chercher des secrets.
  String get secretsPath => hostPath ?? filePath;

  /// Raccourci : exécute une commande avec le jeton d'annulation de l'analyse.
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin}) =>
      runner.run(executable, args, stdin: stdin, cancel: cancel);
}

class AnalyzerResult {
  final ToolRun run;
  final List<Finding> findings;

  /// Données propres à l'outil, reprises dans le rapport (inventaire des
  /// commandes externes…).
  final Object? data;
  const AnalyzerResult(this.run, [this.findings = const [], this.data]);
}

/// Langage traité par un analyseur.
enum ToolLanguage {
  shell,
  python,

  /// Outils indépendants du langage (secrets, règles intégrées, syntaxe).
  any;

  bool accepts(ScriptInfo s) =>
      this == any || (this == python) == s.dialect.isPython;
}

abstract class Analyzer {
  /// Nom de l'outil (clé de configuration).
  String get name;

  /// Langage des scripts que l'outil sait analyser (shell par défaut).
  ToolLanguage get language => ToolLanguage.shell;

  /// L'outil s'applique à [script] (par défaut : selon son langage ; les
  /// outils propres aux Dockerfile ou aux workflows restreignent davantage).
  bool appliesTo(ScriptInfo script) => language.accepts(script);

  Future<AnalyzerResult> analyze(AnalysisContext ctx);

  /// Version de l'outil (null si l'outil est absent, `?` si sa version n'est
  /// pas lisible) : affichée dans le rapport et par `--list-tools`.
  Future<String?> version(CommandRunner runner, CheckConfig config) async =>
      null;
}

/// Extrait le premier numéro de version `x.y[.z]` d'une sortie.
String? extractVersion(String text) =>
    RegExp(r'\d+\.\d+(?:\.\d+)?').firstMatch(text)?.group(0);
