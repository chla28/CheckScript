/// Contrat commun des analyseurs et abstraction de l'exécution de commandes.
library;

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

/// Exécute les outils externes. Remplacé par un faux dans les tests.
abstract class CommandRunner {
  /// Exécute [executable] ; renvoie null si l'exécutable est introuvable.
  Future<CommandResult?> run(String executable, List<String> args);
}

class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner();

  @override
  Future<CommandResult?> run(String executable, List<String> args) async {
    try {
      // LC_ALL=C : messages des outils (bash -n…) en anglais, donc analysables.
      final r = await Process.run(executable, args,
          environment: {'LC_ALL': 'C'}, stdoutEncoding: systemEncoding);
      return CommandResult(r.exitCode, '${r.stdout}', '${r.stderr}');
    } on ProcessException {
      return null;
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

  const AnalysisContext({
    required this.script,
    required this.filePath,
    required this.config,
    required this.lang,
    required this.runner,
  });
}

class AnalyzerResult {
  final ToolRun run;
  final List<Finding> findings;
  const AnalyzerResult(this.run, [this.findings = const []]);
}

abstract class Analyzer {
  /// Nom de l'outil (clé de configuration).
  String get name;

  Future<AnalyzerResult> analyze(AnalysisContext ctx);

  /// Version de l'outil (null si l'outil est absent, `?` si sa version n'est
  /// pas lisible) : affichée dans le rapport et par `--list-tools`.
  Future<String?> version(CommandRunner runner, CheckConfig config) async =>
      null;
}

/// Extrait le premier numéro de version `x.y[.z]` d'une sortie.
String? extractVersion(String text) =>
    RegExp(r'\d+\.\d+(?:\.\d+)?').firstMatch(text)?.group(0);
