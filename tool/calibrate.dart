/// Calibrage : analyse le corpus (test/corpus) avec les outils installés et
/// compare les niveaux obtenus aux plages attendues de labels.yaml.
///
///   dart run tool/calibrate.dart            # tableau de synthèse
///   dart run tool/calibrate.dart --details  # + règles déclenchées par script
///   dart run tool/calibrate.dart --builtin  # règles intégrées seules
///
/// Code de sortie 1 si un script sort de sa plage attendue.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:yaml/yaml.dart';

const grades = ['A', 'B', 'C', 'D', 'E'];

Future<void> main(List<String> args) async {
  final details = args.contains('--details');
  final builtinOnly = args.contains('--builtin');
  final labels =
      loadYaml(File('test/corpus/labels.yaml').readAsStringSync()) as YamlMap;
  var failures = 0;
  stdout.writeln(
      '${'script'.padRight(36)} ${'Séc'.padLeft(5)} ${'Rob'.padLeft(5)} '
      '${'Mnt'.padLeft(5)} ${'Por'.padLeft(5)} ${'Prf'.padLeft(5)}  global  attendu');
  for (final e in labels.entries) {
    final name = '${e.key}';
    final label = e.value as YamlMap;
    final range = [for (final g in label['grades'] as YamlList) '$g'];
    final ctx = {
      for (final c in (label['contexts'] as YamlList?) ?? const [])
        ExecContext.tryParse('$c')!
    };
    var config = CheckConfig(contexts: ctx);
    if (builtinOnly) {
      config = config.withToolsDisabled([
        'shellcheck',
        'shfmt',
        'bashate',
        'checkbashisms',
        'gitleaks',
        'trufflehog',
        'syntax'
      ]);
    }
    final r = await Engine(config: config, lang: Lang.fr)
        .analyzeFile('test/corpus/scripts/$name');
    final ok = grades.indexOf(r.grade) >= grades.indexOf(range.first) &&
        grades.indexOf(r.grade) <= grades.indexOf(range.last);
    if (!ok) failures++;
    stdout.writeln('${name.padRight(36)} '
        '${r.scores.map((s) => s.score.toStringAsFixed(1).padLeft(5)).join(' ')}'
        '  ${r.global.toStringAsFixed(1).padLeft(4)} ${r.grade}  ${range.join('–')}'
        '${ok ? '' : '  ✗'}');
    if (details) {
      final counts = <String, int>{};
      for (final f in r.findings) {
        final k = '${f.ruleId}(${f.severity.label[0]})';
        counts[k] = (counts[k] ?? 0) + 1;
      }
      stdout.writeln(
          '    ${counts.entries.map((c) => c.value > 1 ? '${c.key}×${c.value}' : c.key).join(' ')}');
    }
  }
  stdout.writeln(failures == 0
      ? '\n✓ corpus conforme'
      : '\n✗ $failures script(s) hors plage');
  exit(failures == 0 ? 0 : 1);
}
