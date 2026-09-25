/// Vérifie les messages de commit (Conventional Commits).
///
///   dart run tool/commit_lint.dart FICHIER         message à valider (hook commit-msg)
///   dart run tool/commit_lint.dart --range A..B    commits de l'intervalle (CI)
///
/// Code de sortie 1 si un message n'est pas conforme.
library;

import 'dart:io';

import 'conventional.dart';

Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == '--range') {
    final r =
        await Process.run('git', ['log', '--format=%H%x1f%B%x1e', args[1]]);
    if (r.exitCode != 0) {
      stderr.writeln('git log ${args[1]} : ${r.stderr}');
      exit(2);
    }
    var bad = 0;
    for (final entry in '${r.stdout}'.split('\x1e')) {
      final parts = entry.trim().split('\x1f');
      if (parts.length < 2) continue;
      final errors = lintMessage(parts[1]);
      if (errors.isEmpty) continue;
      bad++;
      stderr.writeln(
          '✗ ${parts[0].substring(0, 7)} ${parts[1].split('\n').first}');
      for (final e in errors) {
        stderr.writeln('    $e');
      }
    }
    stdout.writeln(bad == 0
        ? '✓ messages de commit conformes (Conventional Commits)'
        : '✗ $bad message(s) non conforme(s)');
    exit(bad == 0 ? 0 : 1);
  }
  if (args.length != 1) {
    stderr.writeln('usage : commit_lint.dart FICHIER | --range A..B');
    exit(2);
  }
  final errors = lintMessage(File(args.first).readAsStringSync());
  if (errors.isEmpty) exit(0);
  stderr.writeln('✗ message de commit non conforme (Conventional Commits) :');
  for (final e in errors) {
    stderr.writeln('    $e');
  }
  stderr.writeln('  exemple : feat(gui): ajoute l\'onglet Règles');
  exit(1);
}
