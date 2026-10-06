/// Resserrage de la référence (`--baseline-update`) : les problèmes corrigés
/// en sont retirés, pour que la dette tolérée ne puisse que diminuer.
///
/// Un script n'est resserré que s'il n'a aucun problème nouveau par rapport
/// à la référence : l'analyse actuelle est alors exactement la référence
/// moins les problèmes corrigés, et son rapport la remplace (notes
/// comprises). S'il a des problèmes nouveaux, son entrée reste inchangée :
/// on ne les absorbe pas dans la dette tolérée.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'model/report.dart';
import 'reporters/reporters.dart' show renderJson;

class BaselineUpdate {
  /// Nouveau contenu du fichier de référence.
  final String json;

  /// Scripts resserrés (au moins un problème corrigé retiré).
  final int updated;

  /// Problèmes corrigés retirés de la référence.
  final int removed;

  /// Scripts laissés inchangés à cause de problèmes nouveaux.
  final List<String> refused;

  /// Scripts de la référence sans changement (rien à retirer) ou non
  /// analysés.
  final int unchanged;

  const BaselineUpdate(
      this.json, this.updated, this.removed, this.refused, this.unchanged);
}

/// Resserre la référence [baselineJson] d'après les [reports] d'une analyse
/// faite avec cette référence. Lève [FormatException] si ce n'est pas un
/// rapport check-script.
BaselineUpdate updateBaseline(String baselineJson, List<ScriptReport> reports) {
  final Object? doc;
  try {
    doc = jsonDecode(baselineJson);
  } on FormatException {
    throw const FormatException('baseline: invalid JSON');
  }
  if (doc is! Map || doc['reports'] is! List) {
    throw const FormatException(
        'baseline: check-script JSON report expected ("reports" key)');
  }
  final entries = [for (final e in doc['reports'] as List) e];

  int? indexFor(String path) {
    for (var i = 0; i < entries.length; i++) {
      final f = entries[i] is Map ? '${(entries[i] as Map)['file']}' : '';
      if (f == path || p.normalize(f) == p.normalize(path)) return i;
    }
    final same = [
      for (var i = 0; i < entries.length; i++)
        if (entries[i] is Map &&
            p.basename('${(entries[i] as Map)['file']}') == p.basename(path))
          i
    ];
    return same.length == 1 ? same.first : null;
  }

  var updated = 0, removed = 0;
  final refused = <String>[];
  final touched = <int>{};
  for (final r in reports) {
    final cmp = r.comparison;
    final i = indexFor(r.script.path);
    if (cmp == null || i == null) continue;
    touched.add(i);
    if (cmp.added.isNotEmpty) {
      refused.add(r.script.path);
      continue;
    }
    if (cmp.fixed == 0) continue;
    final fresh = Map<String, Object?>.of(
        (jsonDecode(renderJson([r]))['reports'] as List).first
            as Map<String, dynamic>)
      ..remove('comparison')
      // Le chemin d'origine de la référence fait foi pour l'appariement.
      ..['file'] = (entries[i] as Map)['file'];
    entries[i] = fresh;
    updated++;
    removed += cmp.fixed;
  }
  final out = Map<String, Object?>.of(doc.cast<String, Object?>())
    ..['reports'] = entries;
  return BaselineUpdate(
    const JsonEncoder.withIndent('  ').convert(out),
    updated,
    removed,
    refused,
    entries.length - updated - refused.length,
  );
}
