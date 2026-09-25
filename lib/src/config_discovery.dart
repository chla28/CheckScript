/// Configuration de projet : le `.checkscript.yaml` le plus proche d'un
/// script, pour des réglages par sous-projet (monodépôt, CI).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Nom du fichier de configuration de projet.
const projectConfigName = '.checkscript.yaml';

/// `.checkscript.yaml` le plus proche de [scriptPath] (fichier ou dossier) :
/// son dossier, puis les dossiers parents jusqu'à la racine du dépôt git
/// (dossier qui contient `.git`) ou du système de fichiers ; null sinon.
String? findProjectConfig(String scriptPath) {
  final abs = p.normalize(p.absolute(scriptPath));
  var dir = FileSystemEntity.isDirectorySync(abs) ? abs : p.dirname(abs);
  while (true) {
    final f = File(p.join(dir, projectConfigName));
    if (f.existsSync()) return f.path;
    // La racine du dépôt borne la recherche : un dépôt ne dépend pas d'un
    // fichier posé au-dessus de lui.
    if (FileSystemEntity.typeSync(p.join(dir, '.git')) !=
        FileSystemEntityType.notFound) {
      return null;
    }
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}
