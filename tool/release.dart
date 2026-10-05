/// Publication d'une version à partir des Conventional Commits : version
/// suivante déduite des commits depuis le dernier tag, fichiers de version
/// synchronisés, section du CHANGELOG générée, commit
/// `chore(release): X.Y.Z` et tag annoté `vX.Y.Z`.
///
///   dart run tool/release.dart --dry-run      version et CHANGELOG, sans rien écrire
///   dart run tool/release.dart [--push]       publie (et pousse main + tag)
///   options : --version X.Y.Z (imposer), --trailer "Clé: valeur" (répétable)
///
/// Les notes rédigées sous « ## Non publié » du CHANGELOG sont conservées en
/// tête de la section. Le dépôt doit être propre (fichiers suivis).
library;

import 'dart:io';

import 'conventional.dart';

Future<String> _git(List<String> args, {bool allowFail = false}) async {
  final r = await Process.run('git', args);
  if (r.exitCode != 0 && !allowFail) {
    stderr.writeln('git ${args.join(' ')} : ${r.stderr}');
    exit(2);
  }
  return '${r.stdout}'.trim();
}

/// Fichiers portant la version, et le remplacement à y appliquer.
Map<String, String Function(String, String, String)> versionFiles = {
  'pubspec.yaml': (s, old, v) =>
      s.replaceFirst(RegExp(r'^version: .*$', multiLine: true), 'version: $v'),
  'gui/pubspec.yaml': (s, old, v) => s.replaceFirstMapped(
      RegExp(r'^version: [0-9.]+\+(\d+)$', multiLine: true),
      (m) => 'version: $v+${int.parse(m[1]!) + 1}'),
  'lib/src/version.dart': (s, old, v) =>
      s.replaceFirst(RegExp(r"appVersion = '[^']*'"), "appVersion = '$v'"),
  '.pre-commit-hooks.yaml': (s, old, v) =>
      s.replaceAll('rev: v$old', 'rev: v$v'),
  for (final f in ['doc/user.adoc', 'doc/user.fr.adoc'])
    f: (s, old, v) => s
        .replaceAll('rev: v$old', 'rev: v$v')
        .replaceAll('CheckScript@v$old', 'CheckScript@v$v'),
  // Exemples d'utilisation de l'action GitHub.
  for (final f in ['README.md', 'README.fr.md'])
    f: (s, old, v) => s.replaceAll('CheckScript@v$old', 'CheckScript@v$v'),
  'action.yml': (s, old, v) =>
      s.replaceAll('CheckScript@v$old', 'CheckScript@v$v'),
  'doc/ci/github-actions.yml': (s, old, v) =>
      s.replaceAll('CheckScript@v$old', 'CheckScript@v$v'),
  // Seule la version de check-script (l'exemple contient aussi celle de
  // ShellCheck).
  for (final f in ['doc/developer.adoc', 'doc/developer.fr.adoc'])
    f: (s, old, v) => s.replaceAll(
        '"tool": "check-script", "version": "$old"',
        '"tool": "check-script", "version": "$v"'),
  // Extensions d'éditeurs.
  'editors/vscode/package.json': (s, old, v) =>
      s.replaceFirst('"version": "$old"', '"version": "$v"'),
  'editors/vscode/package-lock.json': (s, old, v) => s.replaceAllMapped(
      RegExp('("name": "check-script",\\s*"version": ")${RegExp.escape(old)}"'),
      (m) => '${m[1]}$v"'),
  'editors/eclipse/pom.xml': (s, old, v) =>
      s.replaceFirst('<version>$old</version>', '<version>$v</version>'),
  'editors/eclipse/bundles/fr.chla28.checkscript/pom.xml': (s, old, v) =>
      s.replaceFirst('<version>$old</version>', '<version>$v</version>'),
  'editors/eclipse/features/fr.chla28.checkscript.feature/pom.xml':
      (s, old, v) =>
          s.replaceFirst('<version>$old</version>', '<version>$v</version>'),
  'editors/eclipse/sites/fr.chla28.checkscript.site/pom.xml': (s, old, v) =>
      s.replaceFirst('<version>$old</version>', '<version>$v</version>'),
  'editors/eclipse/bundles/fr.chla28.checkscript/META-INF/MANIFEST.MF':
      (s, old, v) =>
          s.replaceFirst('Bundle-Version: $old', 'Bundle-Version: $v'),
  'editors/eclipse/features/fr.chla28.checkscript.feature/feature.xml':
      (s, old, v) => s.replaceAll('version="$old"', 'version="$v"'),
  'editors/eclipse/sites/fr.chla28.checkscript.site/category.xml':
      (s, old, v) => s.replaceAll('version="$old"', 'version="$v"'),
  'packaging/rpm/check-script.spec': (s, old, v) =>
      s.replaceAll('global version $old}', 'global version $v}'),
  'packaging/rpm/check-script-gui.spec': (s, old, v) =>
      s.replaceAll('global version $old}', 'global version $v}'),
  'packaging/linux/fr.chla28.check_script_gui.metainfo.xml': (s, old, v) =>
      s.replaceFirst(RegExp(r'<release version="[^"]*" date="[^"]*"/>'),
          '<release version="$v" date="${_today()}"/>'),
};

String _today() => DateTime.now().toIso8601String().substring(0, 10);

Future<void> main(List<String> args) async {
  final dry = args.contains('--dry-run');
  final push = args.contains('--push');
  String? forced;
  final trailers = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--version' && i + 1 < args.length) forced = args[++i];
    if (args[i] == '--trailer' && i + 1 < args.length) trailers.add(args[++i]);
  }
  final root = await _git(['rev-parse', '--show-toplevel']);
  Directory.current = root;

  if (!dry &&
      (await _git(['status', '--porcelain', '--untracked-files=no']))
          .isNotEmpty) {
    stderr.writeln('Modifications non commitées : commiter avant de publier.');
    exit(2);
  }
  final current = RegExp(r'^version: ([0-9.]+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync())![1]!;
  final tag = await _git(['describe', '--tags', '--abbrev=0'], allowFail: true);
  final log = await _git([
    'log',
    '--format=%H%x1f%B%x1e',
    if (tag.isNotEmpty) '$tag..HEAD',
  ]);
  final commits = <Commit>[];
  for (final entry in log.split('\x1e')) {
    final parts = entry.trim().split('\x1f');
    if (parts.length < 2) continue;
    final c = parseCommit(parts[1], hash: parts[0]);
    // Message non conforme (antérieur à l'adoption) : rubrique Maintenance.
    commits.add(c ??
        Commit('chore', null, parts[1].trim().split('\n').first,
            hash: parts[0]));
  }
  final next = forced ?? nextVersion(current, commits);
  if (next == null) {
    stdout.writeln(
        'Aucun commit depuis ${tag.isEmpty ? 'le début' : tag} : rien à publier.');
    return;
  }

  final changelog = File('CHANGELOG.md').readAsStringSync();
  final unreleased =
      RegExp(r'^## Non publié\n([\s\S]*?)(?=^## )', multiLine: true)
          .firstMatch(changelog);
  final section = changelogSection(next, _today(), commits.reversed.toList(),
      manualNotes: unreleased?[1] ?? '');
  stdout.writeln(
      '$current → $next (${commits.length} commit(s) depuis ${tag.isEmpty ? 'le début' : tag})\n');
  stdout.writeln(section);
  if (dry) return;

  for (final e in versionFiles.entries) {
    final f = File(e.key);
    f.writeAsStringSync(e.value(f.readAsStringSync(), current, next));
  }
  File('CHANGELOG.md').writeAsStringSync(unreleased != null
      ? changelog.replaceRange(unreleased.start, unreleased.end, section)
      : changelog.replaceFirst('# Changelog\n\n', '# Changelog\n\n$section'));
  // gui/pubspec.lock reprend la version de la bibliothèque.
  try {
    await Process.run('flutter', ['pub', 'get'], workingDirectory: 'gui');
  } on ProcessException {
    stderr.writeln('flutter absent : gui/pubspec.lock non mis à jour.');
  }

  await _git(['add', 'CHANGELOG.md', 'gui/pubspec.lock', ...versionFiles.keys]);
  await _git([
    'commit',
    '-q',
    '-m',
    [
      'chore(release): $next',
      if (trailers.isNotEmpty) '',
      ...trailers,
    ].join('\n'),
  ]);
  await _git(['tag', '-a', 'v$next', '-m', 'Version $next']);
  stdout.writeln('✓ commit chore(release): $next, tag v$next');
  if (push) {
    await _git(['push', 'origin', 'HEAD']);
    await _git(['push', 'origin', 'v$next']);
    stdout.writeln('✓ poussés vers origin');
  } else {
    stdout.writeln(
        '  pour publier : git push origin HEAD && git push origin v$next');
  }
}
