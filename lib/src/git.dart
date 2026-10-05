/// Fichiers modifiés dans un dépôt git (`--changed-since REF`) : n'analyser
/// que ce qui a changé, en CI ou en pre-commit sur un gros dépôt.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'analyzers/analyzer.dart';

/// Résultat de [changedSince] : chemins absolus normalisés, ou erreur.
typedef ChangedFiles = ({Set<String>? files, String? error});

/// Fichiers modifiés depuis [ref] dans le dépôt qui contient [dir] : commits
/// depuis [ref], modifications indexées ou non, fichiers non suivis (hors
/// `.gitignore`) ; les fichiers supprimés sont écartés.
Future<ChangedFiles> changedSince(String ref,
    {String dir = '.',
    CommandRunner runner = const ProcessCommandRunner()}) async {
  final top =
      await runner.run('git', ['-C', dir, 'rev-parse', '--show-toplevel']);
  if (top == null) return (files: null, error: 'git not found');
  if (top.exitCode != 0) {
    return (files: null, error: 'not a git repository: ${p.absolute(dir)}');
  }
  final root = top.stdout.trim();
  final diff = await runner.run('git', [
    '-C',
    root,
    'diff',
    '--name-only',
    '--diff-filter=ACMRT',
    ref,
    '--',
  ]);
  if (diff == null || diff.exitCode != 0) {
    return (
      files: null,
      error: 'unknown git reference: $ref'
          '${diff == null ? '' : ' (${diff.stderr.trim().split('\n').first})'}'
    );
  }
  final untracked = await runner
      .run('git', ['-C', root, 'ls-files', '--others', '--exclude-standard']);
  final names = [
    ...diff.stdout.split('\n'),
    if (untracked != null && untracked.exitCode == 0)
      ...untracked.stdout.split('\n'),
  ];
  return (
    files: {
      for (final n in names)
        if (n.trim().isNotEmpty) normalizedPath(p.join(root, n.trim()))
    },
    error: null,
  );
}

/// Chemin absolu normalisé, liens symboliques résolus (git renvoie le
/// chemin réel du dépôt) : sert à comparer avec [changedSince].
String normalizedPath(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.normalize(p.absolute(path));
  }
}
