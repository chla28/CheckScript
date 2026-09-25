/// Ouverture d'un script dans l'éditeur, à la ligne d'un problème.
library;

import 'dart:io';

import 'package:check_script/check_script.dart' show hostInvocation, inFlatpak;

/// Éditeurs reconnus : exécutable et arguments ({file}, {line}).
const Map<String, List<String>> knownEditors = {
  'code': ['-g', '{file}:{line}'],
  'codium': ['-g', '{file}:{line}'],
  'gnome-text-editor': ['+{line}', '{file}'],
  'gedit': ['+{line}', '{file}'],
  'kate': ['--line', '{line}', '{file}'],
  'kwrite': ['--line', '{line}', '{file}'],
  'xed': ['+{line}', '{file}'],
  'geany': ['--line', '{line}', '{file}'],
};

/// Premier éditeur connu présent dans le PATH, sous forme de commande
/// (`code -g {file}:{line}`) ; null sinon. Dans un Flatpak, c'est le PATH
/// de l'hôte qui compte.
String? detectEditor({String? path, bool Function(String)? exists}) {
  if (path == null && exists == null && inFlatpak) {
    for (final e in knownEditors.entries) {
      try {
        final (exe, args) = hostInvocation(
            'sh', ['-c', 'command -v "\$1" >/dev/null 2>&1', 'sh', e.key]);
        if (Process.runSync(exe, args).exitCode == 0) {
          return [e.key, ...e.value].join(' ');
        }
      } on ProcessException {
        return null;
      }
    }
    return null;
  }
  final dirs = (path ?? Platform.environment['PATH'] ?? '').split(':');
  final ok = exists ?? (String f) => File(f).existsSync();
  for (final e in knownEditors.entries) {
    if (dirs.any((d) => d.isNotEmpty && ok('$d/${e.key}'))) {
      return [e.key, ...e.value].join(' ');
    }
  }
  return null;
}

/// Commande à lancer pour [template] (mots séparés par des espaces,
/// `{file}` et `{line}` remplacés) ; sans modèle : `xdg-open` (sans ligne).
List<String> editorCommandLine(String? template, String file, int line) {
  if (template == null || template.trim().isEmpty) return ['xdg-open', file];
  return [
    for (final w in template.trim().split(RegExp(r'\s+')))
      w
          .replaceAll('{file}', file)
          .replaceAll('{line}', '${line < 1 ? 1 : line}')
  ];
}

/// Ouvre [file] à la ligne [line] ; renvoie un message d'erreur, ou null.
Future<String?> openInEditor(String? template, String file, int line) async {
  final cmd = editorCommandLine(template ?? detectEditor(), file, line);
  // Dans un Flatpak, l'éditeur est celui de l'hôte.
  final (exe, args) = inFlatpak
      ? hostInvocation(cmd.first, cmd.skip(1).toList())
      : (cmd.first, cmd.skip(1).toList());
  try {
    await Process.start(exe, args, mode: ProcessStartMode.detached);
    return null;
  } on ProcessException catch (e) {
    return '${cmd.first} : ${e.message}';
  }
}
