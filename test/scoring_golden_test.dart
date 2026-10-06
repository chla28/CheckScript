/// Non-régression du barème de notation, sans aucun outil externe :
///
/// 1. notes (globale, niveau, cinq catégories) de chaque script du corpus
///    pour les trois profils, d'après les seules règles intégrées — un
///    changement du barème, des poids ou d'une règle intégrée fait bouger
///    l'instantané. Régénérer avec
///    `UPDATE_GOLDEN=1 dart test test/scoring_golden_test.dart` après avoir
///    vérifié que les écarts sont voulus ;
/// 2. les constantes du barème (poids, plafond, niveaux) sont celles que
///    décrivent les guides utilisateur, en français et en anglais.
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

const _goldenPath = 'test/corpus/expected_scores.txt';

String _fmt(double v) => v.toStringAsFixed(1);

void main() {
  final labels =
      loadYaml(File('test/corpus/labels.yaml').readAsStringSync()) as YamlMap;
  final update = Platform.environment['UPDATE_GOLDEN'] != null;

  /// Notes d'un script pour un profil : « default 1.5 E 0.0 1.3 8.8 10.0 9.0 ».
  Future<String> line(String name, Profile profile) async {
    final ctx = {
      for (final c
          in (labels[name] as YamlMap)['contexts'] as YamlList? ?? const [])
        ExecContext.tryParse('$c')!
    };
    final config = CheckConfig.forProfile(profile)
        .copyWith(contexts: ctx)
        .withToolsDisabled(_external);
    final r = await Engine(runner: noTools(), config: config)
        .analyzeFile('test/corpus/scripts/$name');
    final label = profile == Profile.standard ? 'default' : profile.name;
    return '$label ${_fmt(r.global)} ${r.grade} '
        '${r.scores.map((s) => _fmt(s.score)).join(' ')}';
  }

  Future<String> snapshot() async {
    final b = StringBuffer()
      ..writeln('# Notes du corpus d\'après les règles intégrées seules.')
      ..writeln('# Colonnes : profil, note globale, niveau, puis les notes de')
      ..writeln('# ${Category.values.map((c) => c.name).join(', ')}.')
      ..writeln(
          '# Régénérer : UPDATE_GOLDEN=1 dart test test/scoring_golden_test.dart');
    for (final name in labels.keys.cast<String>()) {
      b.writeln('\n## $name');
      for (final p in [Profile.standard, Profile.strict, Profile.legacy]) {
        b.writeln(await line(name, p));
      }
    }
    return b.toString();
  }

  group('instantané des notes du corpus', () {
    test('notes identiques à test/corpus/expected_scores.txt', () async {
      final current = await snapshot();
      final golden = File(_goldenPath);
      if (update) {
        golden.writeAsStringSync(current);
        return;
      }
      expect(golden.existsSync(), isTrue,
          reason: '$_goldenPath manquant : UPDATE_GOLDEN=1 pour le créer');
      final expected = golden.readAsLinesSync();
      final actual = current.trimRight().split('\n');
      // Écart lisible : première ligne qui diffère, avec son script.
      var script = '';
      for (var i = 0; i < expected.length && i < actual.length; i++) {
        if (expected[i].startsWith('## ')) script = expected[i].substring(3);
        expect(actual[i], expected[i],
            reason: 'Barème modifié ($script) : UPDATE_GOLDEN=1 pour '
                'régénérer si c\'est voulu');
      }
      expect(actual.length, expected.length);
    });

    test('l\'instantané couvre exactement les scripts du corpus', () {
      if (update) return;
      final names = {
        for (final l in File(_goldenPath).readAsLinesSync())
          if (l.startsWith('## ')) l.substring(3)
      };
      expect(names, labels.keys.cast<String>().toSet());
      final scripts = {
        for (final f in Directory('test/corpus/scripts').listSync())
          f.path.split('/').last
      };
      expect(names, scripts,
          reason: 'script du corpus sans entrée (ou inverse)');
    });

    test(
        'profil strict jamais plus clément que standard, legacy jamais plus '
        'sévère', () {
      if (update) return;
      final rows = <String, Map<String, double>>{};
      var name = '';
      for (final l in File(_goldenPath).readAsLinesSync()) {
        if (l.startsWith('## ')) {
          name = l.substring(3);
        } else if (RegExp(r'^(default|strict|legacy) ').hasMatch(l)) {
          final parts = l.split(' ');
          rows.putIfAbsent(name, () => {})[parts[0]] = double.parse(parts[1]);
        }
      }
      expect(rows, isNotEmpty);
      for (final e in rows.entries) {
        final r = e.value;
        expect(r['strict']!, lessThanOrEqualTo(r['default']!),
            reason: '${e.key} : strict > default');
        expect(r['legacy']!, greaterThanOrEqualTo(r['default']!),
            reason: '${e.key} : legacy < default');
      }
    });
  });

  group('constantes du barème = guides utilisateur', () {
    final en = File('doc/user.adoc').readAsStringSync();
    final fr = File('doc/user.fr.adoc').readAsStringSync();

    String num(double v, {bool comma = false}) {
      final s = v == v.roundToDouble() ? '${v.toInt()}' : '$v';
      return comma ? s.replaceAll('.', ',') : s;
    }

    String weights(Profile p, {bool comma = false}) {
      final w = CheckConfig.forProfile(p).scoring.weights;
      return [
        for (final s in Severity.values)
          '${s.label} ${num(w[s]!, comma: comma)}'
      ].join(' · ');
    }

    test('poids du profil standard', () {
      expect(en,
          contains('weight (standard profile): ${weights(Profile.standard)}'));
      expect(
          fr,
          contains(
              'poids (profil standard) : ${weights(Profile.standard, comma: true)}'));
    });

    test('poids des profils strict et legacy', () {
      final s = CheckConfig.forProfile(Profile.strict).scoring;
      expect(
          en,
          contains('Critical ${num(s.weights[Severity.critical]!)}, '
              'High ${num(s.weights[Severity.high]!)}, '
              'Medium ${num(s.weights[Severity.medium]!)}, '
              'Low ${num(s.weights[Severity.low]!)}; attenuation from ${s.referenceLines} lines'));
      expect(
          fr,
          contains('Critical ${num(s.weights[Severity.critical]!)}, '
              'High ${num(s.weights[Severity.high]!)}, '
              'Medium ${num(s.weights[Severity.medium]!)}, '
              'Low ${num(s.weights[Severity.low]!, comma: true)} ; atténuation dès ${s.referenceLines} lignes'));
      final l = CheckConfig.forProfile(Profile.legacy).scoring.weights;
      expect(
          en,
          contains('High ${num(l[Severity.high]!)}, '
              'Medium ${num(l[Severity.medium]!)}, '
              'Low ${num(l[Severity.low]!)}'));
      expect(
          fr,
          contains('High ${num(l[Severity.high]!, comma: true)}, '
              'Medium ${num(l[Severity.medium]!, comma: true)}, '
              'Low ${num(l[Severity.low]!, comma: true)}'));
    });

    test('poids des catégories, plafond et seuil d\'atténuation', () {
      String flat(String t) => t.replaceAll(RegExp(r'\s+'), ' ');
      final c = const ScoringConfig().categoryWeights;
      expect(c[Category.security], 1.5);
      expect(c[Category.robustness], 1.25);
      expect(c[Category.maintainability], 1);
      expect(c[Category.portability], 0.75);
      expect(c[Category.performance], 0.5);
      expect(
          flat(en),
          contains('Security 1.5; Robustness 1.25; Maintainability 1; '
              'Portability 0.75; Performance 0.5'));
      expect(
          flat(fr),
          contains('Sécurité 1,5 ; Robustesse 1,25 ; Maintenabilité 1 ; '
              'Portabilité 0,75 ; Performance 0,5'));
      expect(maxGapToWorst, 1.5);
      expect(flat(en), contains('lowest category score + 1.5'));
      expect(const ScoringConfig().referenceLines, 100);
      expect(en, contains('√(100 / max(100, lines of code))'));
      expect(fr, contains('√(100 / max(100, lignes de code))'));
    });

    test('niveaux A à E et leurs frontières', () {
      expect(en, contains('*A* ≥ 9 · *B* ≥ 7.5 · *C* ≥ 6 · *D* ≥ 4 · *E* < 4'));
      expect(fr, contains('*A* ≥ 9 · *B* ≥ 7,5 · *C* ≥ 6 · *D* ≥ 4 · *E* < 4'));
      final expected = {
        10.0: 'A',
        9.0: 'A',
        8.9: 'B',
        7.5: 'B',
        7.4: 'C',
        6.0: 'C',
        5.9: 'D',
        4.0: 'D',
        3.9: 'E',
        0.0: 'E',
      };
      for (final e in expected.entries) {
        expect(gradeFor(e.key), e.value, reason: '${e.key}');
      }
    });

    test('profil standard : formule décrite = formule calculée', () {
      // 1 règle High déclenchée 8 fois : 2 × (1 + log2 8) = 8 points.
      final f = [
        for (var i = 0; i < 8; i++)
          Finding(
              tool: 'builtin',
              ruleId: 'X1',
              category: Category.security,
              severity: Severity.high,
              line: i + 1,
              message: 'm')
      ];
      final s = scoreCategory(Category.security, f, 10, const ScoringConfig());
      expect(s.score, 2.0);
      // Un script de 400 lignes : Medium/Low atténués de √(100/400) = 0,5,
      // Critical/High intacts.
      final m = Finding(
          tool: 'builtin',
          ruleId: 'M1',
          category: Category.security,
          severity: Severity.medium,
          line: 1,
          message: 'm');
      expect(
          scoreCategory(Category.security, [m], 400, const ScoringConfig())
              .score,
          closeTo(10 - 0.75 * 0.5, 0.05));
    });
  });
}
