import 'dart:math' as math;

import 'package:check_script/check_script.dart';
import 'package:check_script_gui/widgets/common.dart';
import 'package:check_script_gui/widgets/history_chart.dart';
import 'package:check_script_gui/widgets/radar_chart.dart';
import 'package:check_script_gui/widgets/source_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

class NoTools implements CommandRunner {
  @override
  Future<CommandResult?> run(String executable, List<String> args,
          {String? stdin, CancelToken? cancel}) async =>
      null;
}

double _lin(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// Rapport de contraste WCAG entre deux couleurs opaques.
double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('contraste des couleurs (WCAG AA : 4,5:1)', () {
    for (final br in Brightness.values) {
      test('thème ${br.name} : sévérités et notes sur tous les fonds', () {
        final cs = ColorScheme.fromSeed(
            seedColor: const Color(0xFF3C6E71), brightness: br);
        final backgrounds = {
          'surface': cs.surface,
          'lowest': cs.surfaceContainerLowest,
          'low': cs.surfaceContainerLow,
          'container': cs.surfaceContainer,
          'high': cs.surfaceContainerHigh,
          'highest': cs.surfaceContainerHighest,
        };
        final colors = {
          for (final s in Severity.values)
            'sévérité ${s.name}': severityColor(s, br),
          for (final v in [0.0, 4.9, 5.0, 7.4, 7.5, 10.0])
            'note $v': scoreColor(v, br),
        };
        for (final bg in backgrounds.entries) {
          for (final c in colors.entries) {
            expect(contrast(c.value, bg.value), greaterThanOrEqualTo(4.5),
                reason: '${c.key} sur ${bg.key}');
            // Fond teinté des pastilles de sévérité (12 % de la couleur).
            final tinted =
                Color.alphaBlend(c.value.withValues(alpha: 0.12), bg.value);
            expect(contrast(c.value, tinted), greaterThanOrEqualTo(4.5),
                reason: '${c.key} sur pastille ($bg.key)');
          }
        }
      });
    }

    test('les quatre sévérités restent distinguables entre elles', () {
      for (final br in Brightness.values) {
        final cs = {for (final s in Severity.values) s: severityColor(s, br)};
        expect(cs.values.toSet(), hasLength(4));
      }
    });
  });

  group('lecteurs d\'écran', () {
    testWidgets('marge du code : la sévérité est lue, pas seulement vue',
        (tester) async {
      final handle = tester.ensureSemantics();
      final report = (await tester.runAsync(() =>
          Engine(runner: NoTools(), lang: Lang.en).analyze(
              ScriptInfo.fromContent(
                  't.sh', '#!/bin/bash\nchmod 777 /srv\neval "\$CMD"\n'))))!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: SourceView(
                lines: report.script.displayLines, findings: report.findings),
          ),
        ),
      ));
      expect(find.bySemanticsLabel(RegExp('High')), findsWidgets);
      // Le détail des problèmes de la ligne sert d'indication.
      final eval = report.findings.firstWhere((f) => f.ruleId == 'SEC003');
      final node =
          tester.getSemantics(find.bySemanticsLabel(RegExp('High')).first);
      expect(node.label, contains('High'));
      expect(eval.line, 3);
      var hinted = false;
      void visit(SemanticsNode n) {
        if (n.hint.contains('SEC003')) hinted = true;
        n.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      visit(tester.getSemantics(find.byType(SourceView)));
      expect(hinted, isTrue);
      handle.dispose();
    });

    testWidgets('radar et historique ont une description textuelle',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            SizedBox(
              height: 200,
              child: RadarChart(
                  labels: const ['Sécurité', 'Robustesse', 'Maintenabilité'],
                  values: const [3.0, 7.5, 9.0],
                  color: Colors.teal),
            ),
            SizedBox(
              height: 100,
              child: HistoryChart(
                lang: Lang.en,
                entries: [
                  HistoryEntry(
                      DateTime(2026, 1, 1), 5.0, 3, const {}, const {}),
                  HistoryEntry(
                      DateTime(2026, 2, 1), 7.0, 3, const {}, const {}),
                ],
              ),
            ),
          ]),
        ),
      ));
      expect(
          find.bySemanticsLabel(
              RegExp('Sécurité 3.0, Robustesse 7.5, Maintenabilité 9.0')),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('2 analyses: average score 5.0 → 7.0')),
          findsOneWidget);
      handle.dispose();
    });
  });
}
