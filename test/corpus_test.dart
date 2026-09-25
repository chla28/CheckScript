/// Non-régression sur le corpus (test/corpus) :
///
/// 1. instantané des règles intégrées par script (déterministe, sans outil
///    externe) — régénérer avec `UPDATE_GOLDEN=1 dart test test/corpus_test.dart`
///    après avoir vérifié que les écarts sont voulus ;
/// 2. règles obligatoires / interdites de labels.yaml ;
/// 3. plages de niveaux attendues avec les outils installés (calibrage),
///    ignoré si ShellCheck est absent.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'helpers.dart';

const _external = [
  'shellcheck',
  'shfmt',
  'bashate',
  'checkbashisms',
  'gitleaks',
  'trufflehog',
  'syntax',
  'ruff',
  'bandit',
  'semgrep',
  'mypy',
  'pyright',
  'pylint',
  'radon',
  'vermin',
];

/// Contrôle des niveaux : Semgrep écarté (règles téléchargées, non figées).
CheckConfig _gradeConfig(Set<ExecContext> ctx) =>
    CheckConfig(contexts: ctx).withToolsDisabled(['semgrep']);
const _grades = ['A', 'B', 'C', 'D', 'E'];

void main() {
  final labels =
      loadYaml(File('test/corpus/labels.yaml').readAsStringSync()) as YamlMap;
  final update = Platform.environment['UPDATE_GOLDEN'] != null;
  bool has(String tool) =>
      Process.runSync('sh', ['-c', 'command -v $tool']).exitCode == 0;
  final hasShellcheck = has('shellcheck');
  final hasPythonTools = has('ruff') && has('bandit');

  for (final e in labels.entries) {
    final name = '${e.key}';
    final label = e.value as YamlMap;
    final ctx = {
      for (final c in (label['contexts'] as YamlList?) ?? const [])
        ExecContext.tryParse('$c')!
    };
    final path = 'test/corpus/scripts/$name';
    final python = name.endsWith('.py');

    group(name, () {
      late ScriptReport builtinOnly;
      setUpAll(() async {
        builtinOnly = await Engine(
          runner: noTools(),
          config: CheckConfig(contexts: ctx).withToolsDisabled(_external),
        ).analyzeFile(path);
      });

      test('instantané des règles intégrées', () {
        final snapshot = [
          for (final f in builtinOnly.findings)
            '${f.ruleId}@${f.line} ${f.severity.name}'
        ]..sort();
        final golden = File('test/corpus/expected/$name.txt');
        if (update || !golden.existsSync()) {
          golden
            ..createSync(recursive: true)
            ..writeAsStringSync('${snapshot.join('\n')}\n');
        }
        final expected =
            golden.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
        expect(snapshot, expected,
            reason: 'Écart avec test/corpus/expected/$name.txt '
                '(UPDATE_GOLDEN=1 pour régénérer si voulu)');
      });

      test('règles obligatoires et interdites', () {
        final found = ids(builtinOnly.findings);
        for (final r in (label['must'] as YamlList?) ?? const []) {
          if ('$r'.startsWith('SC')) continue;
          expect(found, contains('$r'), reason: '$r attendu');
        }
        for (final r in (label['mustNot'] as YamlList?) ?? const []) {
          expect(found, isNot(contains('$r')), reason: '$r non attendu');
        }
      });

      test('niveau dans la plage attendue (outils installés)', () async {
        final r = await Engine(config: _gradeConfig(ctx)).analyzeFile(path);
        final range = [for (final g in label['grades'] as YamlList) '$g'];
        final i = _grades.indexOf(r.grade);
        expect(
            i >= _grades.indexOf(range.first) &&
                i <= _grades.indexOf(range.last),
            isTrue,
            reason:
                '$name : ${r.global} (${r.grade}), attendu ${range.join('–')}');
      },
          skip: python
              ? (hasPythonTools ? null : 'Ruff / Bandit non installés')
              : (hasShellcheck ? null : 'ShellCheck non installé'));

      if (label['defaultGrades'] != null) {
        test('niveau sans contexte déclaré (outils installés)', () async {
          final r =
              await Engine(config: _gradeConfig(const {})).analyzeFile(path);
          final range = [
            for (final g in label['defaultGrades'] as YamlList) '$g'
          ];
          final i = _grades.indexOf(r.grade);
          expect(
              i >= _grades.indexOf(range.first) &&
                  i <= _grades.indexOf(range.last),
              isTrue,
              reason:
                  '$name : ${r.global} (${r.grade}), attendu ${range.join('–')}');
        },
            skip: python
                ? (hasPythonTools ? null : 'Ruff / Bandit non installés')
                : (hasShellcheck ? null : 'ShellCheck non installé'));
      }
    });
  }
}
