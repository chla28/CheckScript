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

class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner();

  @override
  Future<CommandResult?> run(String executable, List<String> args,
      {String? stdin, CancelToken? cancel}) async {
    final Process p;
    try {
      // LC_ALL=C : messages des outils (bash -n…) en anglais, donc analysables.
      p = await Process.start(executable, args, environment: {'LC_ALL': 'C'});
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

  const AnalysisContext({
    required this.script,
    required this.filePath,
    required this.config,
    required this.lang,
    required this.runner,
    this.cancel,
  });

  /// Raccourci : exécute une commande avec le jeton d'annulation de l'analyse.
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin}) =>
      runner.run(executable, args, stdin: stdin, cancel: cancel);
}

class AnalyzerResult {
  final ToolRun run;
  final List<Finding> findings;
  const AnalyzerResult(this.run, [this.findings = const []]);
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

  Future<AnalyzerResult> analyze(AnalysisContext ctx);

  /// Version de l'outil (null si l'outil est absent, `?` si sa version n'est
  /// pas lisible) : affichée dans le rapport et par `--list-tools`.
  Future<String?> version(CommandRunner runner, CheckConfig config) async =>
      null;
}

/// Extrait le premier numéro de version `x.y[.z]` d'une sortie.
String? extractVersion(String text) =>
    RegExp(r'\d+\.\d+(?:\.\d+)?').firstMatch(text)?.group(0);
