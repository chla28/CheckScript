/// Conventional Commits (https://www.conventionalcommits.org) pour le dépôt
/// CheckScript : validation des messages, montée de version et section du
/// CHANGELOG déduites des commits.
///
/// Format : `type(portée)!: description`, types et portées en anglais,
/// description en français. `BREAKING CHANGE:` (corps) ou `!` : changement
/// incompatible.
library;

/// Types acceptés et titre de leur rubrique dans le CHANGELOG (null : pas
/// de rubrique propre, regroupé dans « Maintenance »).
const Map<String, String?> commitTypes = {
  'feat': 'Fonctionnalités',
  'fix': 'Correctifs',
  'perf': 'Performances',
  'refactor': 'Refactorisation',
  'docs': 'Documentation',
  'test': 'Tests',
  'build': 'Construction et paquets',
  'ci': 'Intégration continue',
  'style': null,
  'chore': null,
  'revert': 'Retours arrière',
};

/// Longueur maximale de la première ligne.
const maxSubjectLength = 100;

final _header = RegExp(
    r'^(?<type>[a-z]+)(?:\((?<scope>[a-z0-9][a-z0-9_./-]*)\))?(?<bang>!)?: (?<desc>\S.*)$');

/// Messages générés par git, acceptés tels quels.
final _generated = RegExp(r'^(Merge |Revert "|fixup! |squash! |amend! )');

class Commit {
  final String type;
  final String? scope;
  final String description;
  final bool breaking;
  final String hash;

  const Commit(this.type, this.scope, this.description,
      {this.breaking = false, this.hash = ''});
}

/// Erreurs du message de commit [message] (vide : conforme).
List<String> lintMessage(String message) {
  final lines = message
      .split('\n')
      .where((l) => !l.startsWith('#')) // commentaires de l'éditeur git
      .toList();
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  if (lines.isEmpty) return ['message vide'];
  final subject = lines.first.trimRight();
  if (_generated.hasMatch(subject)) return const [];
  final errors = <String>[];
  final m = _header.firstMatch(subject);
  if (m == null) {
    errors.add('première ligne attendue : type(portée): description '
        '(types : ${commitTypes.keys.join(', ')})');
  } else {
    final type = m.namedGroup('type')!;
    if (!commitTypes.containsKey(type)) {
      errors.add(
          'type inconnu « $type » (types : ${commitTypes.keys.join(', ')})');
    }
    if (m.namedGroup('desc')!.endsWith('.')) {
      errors.add('pas de point final dans la description');
    }
  }
  if (subject.length > maxSubjectLength) {
    errors.add('première ligne trop longue '
        '(${subject.length} > $maxSubjectLength caractères)');
  }
  if (lines.length > 1 && lines[1].trim().isNotEmpty) {
    errors.add('ligne vide attendue après la première ligne');
  }
  return errors;
}

/// Commit analysé depuis son message, ou null s'il n'est pas conforme.
Commit? parseCommit(String message, {String hash = ''}) {
  final lines = message.trim().split('\n');
  final m = _header.firstMatch(lines.first.trim());
  if (m == null || !commitTypes.containsKey(m.namedGroup('type'))) return null;
  final breaking = m.namedGroup('bang') != null ||
      lines.skip(1).any((l) => RegExp(r'^BREAKING[ -]CHANGE: ').hasMatch(l));
  return Commit(m.namedGroup('type')!, m.namedGroup('scope'),
      m.namedGroup('desc')!.trim(),
      breaking: breaking, hash: hash);
}

/// Version suivante (x.y.z) selon les commits : changement incompatible →
/// majeure (mineure tant que la version est 0.x), `feat` → mineure, tout
/// autre changement → correctif. Null s'il n'y a aucun commit.
String? nextVersion(String current, List<Commit> commits) {
  if (commits.isEmpty) return null;
  final p = current.split('.').map(int.parse).toList();
  final breaking = commits.any((c) => c.breaking);
  final feat = commits.any((c) => c.type == 'feat');
  if (breaking && p[0] > 0) return '${p[0] + 1}.0.0';
  if (breaking || feat) return '${p[0]}.${p[1] + 1}.0';
  return '${p[0]}.${p[1]}.${p[2] + 1}';
}

/// Section du CHANGELOG pour [version] : notes rédigées à la main
/// ([manualNotes], section « Non publié ») puis commits par rubrique.
String changelogSection(String version, String date, List<Commit> commits,
    {String manualNotes = ''}) {
  final b = StringBuffer('## $version — $date\n\n');
  if (manualNotes.trim().isNotEmpty) b.writeln('${manualNotes.trim()}\n');
  String line(Commit c) =>
      '- ${c.scope == null ? '' : '**${c.scope}** : '}${c.description}'
      '${c.hash.isEmpty ? '' : ' (${c.hash.substring(0, c.hash.length < 7 ? c.hash.length : 7)})'}';
  final breaking = commits.where((c) => c.breaking).toList();
  if (breaking.isNotEmpty) {
    b.writeln('### Changements incompatibles\n');
    breaking.map(line).forEach(b.writeln);
    b.writeln();
  }
  final groups = <String, List<Commit>>{};
  for (final c in commits) {
    (groups[commitTypes[c.type] ?? 'Maintenance'] ??= []).add(c);
  }
  final order = [
    ...{
      for (final t in commitTypes.values)
        if (t != null) t
    },
    'Maintenance',
  ];
  for (final title in order) {
    final cs = groups[title];
    if (cs == null) continue;
    b.writeln('### $title\n');
    cs.map(line).forEach(b.writeln);
    b.writeln();
  }
  return b.toString();
}
