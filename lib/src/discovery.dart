/// Découverte des scripts shell et Python d'un dossier (CLI et interface
/// graphique).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'embedded.dart';

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
Future<List<String>?> collectScripts(String target,
    {bool embedded = true}) async {
  final type = await FileSystemEntity.type(target);
  if (type == FileSystemEntityType.file) return [target];
  if (type != FileSystemEntityType.directory) return null;
  final found = <String>[];
  await for (final e
      in Directory(target).list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: target);
    if (p.split(rel).any((s) =>
        (s.startsWith('.') && !(embedded && _hiddenHosts.contains(s))) ||
        _vendorDirs.contains(s))) {
      continue;
    }
    if (_scriptExt.contains(p.extension(e.path).toLowerCase())) {
      found.add(e.path);
      continue;
    }
    if (embedded && await _hasEmbedded(e)) {
      found.add(e.path);
      continue;
    }
    if (p.extension(e.path).isNotEmpty) continue;
    try {
      final head = await e.openRead(0, 128).first;
      if (_scriptShebang
          .hasMatch(String.fromCharCodes(head).split('\n').first)) {
        found.add(e.path);
      }
    } on Object {
      // Fichier illisible ou vide : ignoré.
    }
  }
  found.sort();
  return found;
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
