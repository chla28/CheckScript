/// Découverte des scripts shell et Python d'un dossier (CLI et interface
/// graphique).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'embedded.dart';
import 'ignore.dart';

final _scriptShebang =
    RegExp(r'^#!.*\b(?:(?:ba|da|k|mk|z)?sh|python[23]?(?:\.\d+)?)\b');
const _scriptExt = {'.sh', '.bash', '.ksh', '.dash', '.zsh', '.py', '.pyw'};

/// Dossiers de dépendances tierces, jamais parcourus (les dossiers cachés,
/// dont `.venv` et `.git`, sont déjà exclus).
const _vendorDirs = {'venv', 'site-packages', '__pycache__', 'node_modules'};

/// Dossiers et fichiers cachés parcourus malgré tout : ils contiennent des
/// scripts intégrés (CI).
const _hiddenHosts = {'.github', '.gitlab', '.gitlab-ci.yml'};

/// Fichier → [fichier] ; dossier → scripts shell et Python qu'il contient
/// (extension ou shebang), récursivement, dossiers cachés et de dépendances
/// exclus ; null si introuvable. Avec [embedded], aussi les fichiers
/// contenant des scripts intégrés (Dockerfile, Makefile, CI, Ansible) qui
/// en ont au moins un.
///
/// Dans un dossier, les chemins correspondant aux motifs [exclude] (format
/// `.gitignore`, relatifs au dossier) ou au fichier `.checkscriptignore` de
/// sa racine (sauf [useIgnoreFile] faux) ne sont pas analysés. Un fichier
/// donné explicitement l'est toujours.
Future<List<String>?> collectScripts(String target,
    {bool embedded = true,
    Iterable<String> exclude = const [],
    bool useIgnoreFile = true}) async {
  final type = await FileSystemEntity.type(target);
  if (type == FileSystemEntityType.file) return [target];
  if (type != FileSystemEntityType.directory) return null;
  final ignore = IgnoreRules([
    if (useIgnoreFile) ...IgnoreRules.readFile(p.join(target, ignoreFileName)),
    ...exclude,
  ]);
  final found = <String>[];
  await for (final e
      in Directory(target).list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final relative = p.relative(e.path, from: target);
    if (isExcluded(relative, embedded: embedded)) continue;
    if (ignore.ignores(p.posix.joinAll(p.split(relative)))) continue;
    if (await isScriptFile(e.path, embedded: embedded)) found.add(e.path);
  }
  found.sort();
  return found;
}

/// Chemin (relatif au dossier parcouru) exclu de la découverte : dossiers
/// cachés (sauf ceux de la CI avec [embedded]) et de dépendances.
bool isExcluded(String relative, {bool embedded = true}) =>
    p.split(relative).any((s) =>
        (s.startsWith('.') &&
            s != '.' &&
            !(embedded && _hiddenHosts.contains(s))) ||
        _vendorDirs.contains(s));

/// Le fichier est un script à analyser : extension de script, fichier hôte
/// de scripts intégrés (avec [embedded]), ou shebang d'un shell ou de
/// Python pour un fichier sans extension.
Future<bool> isScriptFile(String path, {bool embedded = true}) async {
  final ext = p.extension(path).toLowerCase();
  if (_scriptExt.contains(ext)) return true;
  final f = File(path);
  if (embedded && await _hasEmbedded(f)) return true;
  if (ext.isNotEmpty) return false;
  try {
    final head = await f.openRead(0, 128).first;
    return _scriptShebang
        .hasMatch(String.fromCharCodes(head).split('\n').first);
  } on Object {
    return false; // illisible ou vide
  }
}

/// Taille maximale d'un fichier hôte examiné.
const _maxHostSize = 1 << 20;

Future<bool> _hasEmbedded(File f) async {
  final path = f.path;
  final lower = path.toLowerCase();
  final yaml = lower.endsWith('.yml') || lower.endsWith('.yaml');
  if (embeddedKindForPath(path) == null && !yaml) return false;
  try {
    if (await f.length() > _maxHostSize) return false;
    final content = (await f.readAsString()).replaceAll('\r\n', '\n');
    final kind = detectEmbedded(path, content);
    return kind != null && extractEmbedded(kind, content).blocks.isNotEmpty;
  } on Object {
    return false; // illisible ou non textuel
  }
}
