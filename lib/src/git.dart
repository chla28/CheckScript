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

/// Fichiers de l'index (ajoutés, copiés, modifiés, renommés) du dépôt qui
/// contient [dir] : racine du dépôt et chemins relatifs à cette racine.
Future<({String? root, List<String> files, String? error})> stagedFiles(
    {String dir = '.',
    CommandRunner runner = const ProcessCommandRunner()}) async {
  final top =
      await runner.run('git', ['-C', dir, 'rev-parse', '--show-toplevel']);
  if (top == null) {
    return (root: null, files: <String>[], error: 'git not found');
  }
  if (top.exitCode != 0) {
    return (
      root: null,
      files: <String>[],
      error: 'not a git repository: ${p.absolute(dir)}'
    );
  }
  final root = top.stdout.trim();
  final r = await runner.run('git',
      ['-C', root, 'diff', '--cached', '--name-only', '--diff-filter=ACMR']);
  if (r == null || r.exitCode != 0) {
    return (root: root, files: <String>[], error: 'git diff --cached failed');
  }
  return (
    root: root,
    files: [
      for (final n in r.stdout.split('\n'))
        if (n.trim().isNotEmpty) n.trim()
    ],
    error: null,
  );
}

/// Contenu d'un fichier tel qu'il est dans l'index (null s'il n'y est pas).
Future<String?> indexContent(String root, String relativePath,
    {CommandRunner runner = const ProcessCommandRunner()}) async {
  final r = await runner.run('git', ['-C', root, 'show', ':$relativePath']);
  return r == null || r.exitCode != 0 ? null : r.stdout;
}

/// Lignes ajoutées ou modifiées depuis [ref], par fichier (clé : chemin
/// normalisé, voir [normalizedPath]). Un fichier non suivi est entièrement
/// nouveau : sa valeur est null (toutes les lignes comptent). Null pour
/// l'ensemble si git échoue.
Future<Map<String, Set<int>?>?> changedLines(String ref,
    {String dir = '.',
    CommandRunner runner = const ProcessCommandRunner()}) async {
  final top =
      await runner.run('git', ['-C', dir, 'rev-parse', '--show-toplevel']);
  if (top == null || top.exitCode != 0) return null;
  final root = top.stdout.trim();
  final diff = await runner.run('git', [
    '-C', root, 'diff', '-U0', '--no-color', '--diff-filter=ACMRT', ref,
    '--', //
  ]);
  if (diff == null || diff.exitCode != 0) return null;
  final out = <String, Set<int>?>{};
  out.addAll(parseChangedLines(diff.stdout, root));
  final untracked = await runner
      .run('git', ['-C', root, 'ls-files', '--others', '--exclude-standard']);
  if (untracked != null && untracked.exitCode == 0) {
    for (final n in untracked.stdout.split('\n')) {
      if (n.trim().isNotEmpty) {
        out[normalizedPath(p.join(root, n.trim()))] = null;
      }
    }
  }
  return out;
}

/// Lit une sortie `git diff -U0` : lignes ajoutées ou modifiées par fichier
/// (`@@ -a,b +c,d @@` : les lignes c à c+d-1 ; d = 0 pour une suppression).
Map<String, Set<int>> parseChangedLines(String diff, String root) {
  final out = <String, Set<int>>{};
  Set<int>? current;
  for (final l in diff.split('\n')) {
    if (l.startsWith('+++ ')) {
      final name = l.substring(4).trim();
      current = name == '/dev/null'
          ? null
          : (out[normalizedPath(p.join(root, name.replaceFirst('b/', '')))] =
              <int>{});
      continue;
    }
    final m = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@').firstMatch(l);
    if (m == null || current == null) continue;
    final start = int.parse(m[1]!);
    final count = m[2] == null ? 1 : int.parse(m[2]!);
    for (var i = 0; i < count; i++) {
      current.add(start + i);
    }
  }
  return out;
}

/// [path] n'est ni dans l'arbre de travail ni dans le dossier git du dépôt
/// qui contient [dir] : cas d'un `core.hooksPath` global ou système, partagé
/// entre dépôts. Faux si git ne répond pas.
Future<bool> isOutsideRepository(String path, String dir,
    {CommandRunner runner = const ProcessCommandRunner()}) async {
  // Liens symboliques résolus des deux côtés, y compris pour un dossier de
  // hooks pas encore créé (résolution depuis [dir]).
  final base = normalizedPath(dir);
  String resolve(String x) =>
      normalizedPath(p.normalize(p.isAbsolute(x) ? x : p.join(base, x)));
  final target =
      resolve(p.isAbsolute(path) ? path : p.relative(path, from: dir));
  var known = false;
  // Interrogés séparément : un dépôt nu n'a pas d'arbre de travail.
  for (final option in const ['--show-toplevel', '--git-common-dir']) {
    final r = await runner.run('git', ['-C', dir, 'rev-parse', option]);
    if (r == null || r.exitCode != 0) continue;
    known = true;
    final root = resolve(r.stdout.trim());
    if (p.equals(root, target) || p.isWithin(root, target)) return false;
  }
  return known;
}
