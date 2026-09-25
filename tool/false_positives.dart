/// Synthèse des faux positifs signalés depuis l'interface (ou le fichier
/// passé en argument) : nombre de cas par règle, avec leurs extraits
/// anonymisés, pour ajouter des cas au corpus et corriger les règles.
///
///   dart run tool/false_positives.dart [FICHIER.jsonl] [--details]
library;

import 'dart:io';

import 'package:check_script/check_script.dart';

Future<void> main(List<String> args) async {
  final details = args.contains('--details');
  final path = args.where((a) => !a.startsWith('--')).firstOrNull;
  final log =
      path == null ? FalsePositiveLog.standard() : FalsePositiveLog(File(path));
  if (log == null) {
    stderr.writeln('Emplacement du journal inconnu (HOME absent).');
    exit(2);
  }
  final cases = await log.read();
  stdout.writeln('${log.file.path} : ${cases.length} cas');
  final byRule = <String, List<Map<String, Object?>>>{};
  for (final c in cases) {
    (byRule['${c['tool']}/${c['rule']}'] ??= []).add(c);
  }
  final sorted = byRule.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in sorted) {
    stdout.writeln('${e.value.length.toString().padLeft(4)}  ${e.key}');
    if (!details) continue;
    for (final c in e.value) {
      final ctx = (c['context'] as List? ?? const []);
      final focus = (c['focus'] as num?)?.toInt() ?? -1;
      stdout.writeln('      ${c['date']}  ${c['comment'] ?? ''}');
      for (var i = 0; i < ctx.length; i++) {
        stdout.writeln(
            '      ${i == focus ? '▶' : ' '} ${ctx[i] ?? '(ligne masquée)'}');
      }
    }
  }
}
