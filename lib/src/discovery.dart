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
/// (extension ou shebang) : ceux de son niveau seulement, ou de toute son
/// arborescence avec [recursive] (dossiers cachés et de dépendances exclus) ;
/// null si introuvable. Avec [embedded], aussi les fichiers
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
    bool useIgnoreFile = true,
    bool recursive = false}) async {
  final type = await FileSystemEntity.type(target);
  if (type == FileSystemEntityType.file) return [target];
  if (type != FileSystemEntityType.directory) return null;
  final ignore = IgnoreRules([
    if (useIgnoreFile) ...IgnoreRules.readFile(p.join(target, ignoreFileName)),
    ...exclude,
  ]);
  final found = <String>[];
  await for (final e
      in Directory(target).list(recursive: recursive, followLinks: false)) {
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

/// La cible contient un joker (`*`, `?`, `[…]`).
bool hasGlob(String target) => target.contains(RegExp(r'[*?\[]'));

/// Développe les jokers des [targets] (le shell ne le fait pas quand le motif
/// est protégé par des guillemets, ou sous Windows). Une cible sans joker, ou
/// qui existe telle quelle, est conservée ; `-` (entrée standard) aussi.
///
/// Motifs : `*` et `?` ne franchissent pas un `/`, `**` traverse les
/// dossiers, `[abc]` est une classe de caractères. Un motif sans `/` ne
/// s'applique qu'au dossier courant, ou à toute l'arborescence avec
/// [recursive] (comme `find -name`). Seuls les dossiers et les scripts sont
/// retenus. Les fichiers et dossiers cachés ne sont
/// retenus que si le motif les nomme explicitement (`.*`).
///
/// Retourne les chemins correspondants (triés, sans doublon) ; un motif sans
/// résultat est conservé tel quel pour que l'appelant signale « Introuvable ».
Future<List<String>> expandTargets(Iterable<String> targets,
    {bool recursive = false, bool embedded = true}) async {
  final out = <String>[];
  void add(String path) {
    if (!out.contains(path)) out.add(path);
  }

  for (final t in targets) {
    if (t == '-' ||
        !hasGlob(t) ||
        await FileSystemEntity.type(t) != FileSystemEntityType.notFound) {
      add(t);
      continue;
    }
    // Un motif large (`*`) ne ramène que des dossiers et des scripts.
    final found = <String>[
      for (final m in await _expandGlob(t, recursive))
        if (await FileSystemEntity.isDirectory(m) ||
            await isScriptFile(m, embedded: embedded))
          m
    ];
    if (found.isEmpty) {
      add(t);
    } else {
      found.forEach(add);
    }
  }
  return out;
}

Future<List<String>> _expandGlob(String pattern, bool recursive) async {
  // Racine de la recherche : segments sans joker en tête du motif.
  final parts = p.split(pattern);
  var i = 0;
  while (i < parts.length - 1 && !hasGlob(parts[i])) {
    i++;
  }
  final root = i == 0 ? '.' : p.joinAll(parts.sublist(0, i));
  final rest = parts.sublist(i);
  final anywhere = recursive && rest.length == 1;
  final re = _globToRegExp(rest.join('/'));
  final prefix = i == 0 ? '' : '${p.joinAll(parts.sublist(0, i))}/';
  if (!await Directory(root).exists()) return const [];
  final deep = anywhere || rest.contains('**');
  final matches = <String>[];
  await for (final e
      in Directory(root).list(recursive: deep, followLinks: false)) {
    final relative = p.posix.joinAll(p.split(p.relative(e.path, from: root)));
    final name = p.basename(relative);
    final ok = anywhere
        ? _globToRegExp(rest.first).hasMatch(name)
        : re.hasMatch(relative);
    if (!ok) continue;
    // Chemins cachés ou de dépendances traversés par une recherche en
    // profondeur : exclus, sauf si le motif nomme le dossier caché.
    if (deep &&
        isExcluded(p.dirname(relative) == '.' ? '' : p.dirname(relative))) {
      continue;
    }
    if (name.startsWith('.') && !rest.last.startsWith('.')) continue;
    matches.add(i == 0
        ? p.normalize(e.path).replaceFirst('./', '')
        : '$prefix$relative');
  }
  matches.sort();
  return matches;
}

RegExp _globToRegExp(String glob) {
  final b = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final c = glob[i];
    if (c == '*') {
      if (i + 1 < glob.length && glob[i + 1] == '*') {
        i++;
        // `**/` : zéro ou plusieurs dossiers.
        if (i + 1 < glob.length && glob[i + 1] == '/') {
          i++;
          b.write('(?:.*/)?');
        } else {
          b.write('.*');
        }
      } else {
        b.write('[^/]*');
      }
    } else if (c == '?') {
      b.write('[^/]');
    } else if (c == '[') {
      final end = glob.indexOf(']', i + 1);
      if (end < 0) {
        b.write(r'\[');
      } else {
        var cls = glob.substring(i + 1, end);
        if (cls.startsWith('!')) cls = '^${cls.substring(1)}';
        b.write('[${cls.replaceAll(r'\', r'\\')}]');
        i = end;
      }
    } else {
      b.write(RegExp.escape(c));
    }
  }
  b.write(r'$');
  return RegExp(b.toString());
}
