/// Surveillance des scripts : lots de fichiers modifiés, pour réanalyser à
/// chaque enregistrement (`--watch`, vue Dossier de l'interface).
///
/// La surveillance récursive de Dart n'est pas récursive sous Linux :
/// chaque dossier est surveillé séparément (les dossiers créés ensuite
/// aussi). Le dossier plutôt que le fichier : beaucoup d'éditeurs
/// enregistrent par renommage.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'discovery.dart' show isExcluded;

/// Émet, après [debounce] sans nouvel événement, les chemins absolus des
/// fichiers créés, modifiés ou renommés sous [targets] (fichiers ou
/// dossiers). Les dossiers cachés et de dépendances sont ignorés, comme
/// par la découverte des scripts.
Stream<Set<String>> watchTargets(List<String> targets,
    {Duration debounce = const Duration(milliseconds: 400),
    bool embedded = true}) {
  final subs = <String, StreamSubscription<FileSystemEvent>>{};
  final pending = <String>{};
  Timer? timer;
  late final StreamController<Set<String>> out;

  final files = <String>{}; // cibles fichiers
  final roots = <String>[]; // cibles dossiers

  bool wanted(String path) {
    if (files.contains(path)) return true;
    for (final r in roots) {
      if (p.isWithin(r, path)) {
        return !isExcluded(p.relative(path, from: r), embedded: embedded);
      }
    }
    return false;
  }

  void flush() {
    if (pending.isEmpty || out.isClosed) return;
    out.add(Set.of(pending));
    pending.clear();
  }

  void hit(String path) {
    if (!wanted(path)) return;
    pending.add(path);
    timer?.cancel();
    timer = Timer(debounce, flush);
  }

  late void Function(String) watchDir;
  void onEvent(FileSystemEvent e) {
    final path = e is FileSystemMoveEvent ? e.destination ?? e.path : e.path;
    if (e.isDirectory) {
      if (e.type == FileSystemEvent.create && wanted(path)) {
        watchDir(path);
        // Fichiers déjà présents (dossier copié d'un bloc).
        try {
          for (final f in Directory(path).listSync(recursive: true)) {
            if (f is File) hit(f.path);
            if (f is Directory && wanted(f.path)) watchDir(f.path);
          }
        } on FileSystemException {
          // Dossier déjà supprimé.
        }
      }
      return;
    }
    if (e.type == FileSystemEvent.delete) return;
    hit(path);
  }

  watchDir = (String dir) {
    if (subs.containsKey(dir)) return;
    try {
      subs[dir] = Directory(dir).watch().listen(onEvent, onError: (_) {});
    } on FileSystemException {
      // Surveillance impossible (système de fichiers) : ignorée.
    }
  };

  out = StreamController<Set<String>>(
    onListen: () {
      for (final t in targets) {
        final abs = p.normalize(p.absolute(t));
        if (FileSystemEntity.isDirectorySync(abs)) {
          roots.add(abs);
          watchDir(abs);
          for (final d in Directory(abs)
              .listSync(recursive: true, followLinks: false)
              .whereType<Directory>()) {
            if (wanted(d.path)) watchDir(d.path);
          }
        } else {
          files.add(abs);
          watchDir(p.dirname(abs));
        }
      }
    },
    onCancel: () async {
      timer?.cancel();
      for (final s in subs.values) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return out.stream;
}
