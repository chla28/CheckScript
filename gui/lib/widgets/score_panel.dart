/// Synthèse des notes : note globale, radar, tableau des sévérités par
/// catégorie, comparaison avec la référence.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'radar_chart.dart';

class ScorePanel extends StatelessWidget {
  const ScorePanel({super.key, required this.report, required this.lang});

  final ScriptReport report;
  final Lang lang;

  @override
  Widget build(BuildContext context) {
    final t = Messages(lang);
    final theme = Theme.of(context);
    final b = theme.brightness;
    final cmp = report.comparison;
    final color = scoreColor(report.global, b);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(fmtScore(report.global, lang),
            style: theme.textTheme.displaySmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        Text(' /10', style: theme.textTheme.titleMedium),
        const SizedBox(width: 12),
        Chip(
          label: Text(report.grade,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          side: BorderSide(color: color),
        ),
        const Spacer(),
        if (cmp != null) DeltaChip(report.global, cmp.previousGlobal, lang),
      ]),
      Text(t.globalScore, style: theme.textTheme.labelMedium),
      if (cmp != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              t.comparisonLine(cmp.added.length, cmp.fixed, cmp.unchanged),
              style: theme.textTheme.bodySmall),
        ),
      SizedBox(
        height: 220,
        child: RadarChart(
          labels: [for (final c in Category.values) t.category(c)],
          values: [for (final s in report.scores) s.score],
          previous: cmp == null
              ? null
              : [for (final c in Category.values) cmp.previousScores[c] ?? 10],
          color: color,
        ),
      ),
      Table(
        columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(72)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            _h(context, t.category_),
            _h(context, t.score, right: true),
            for (final s in Severity.values)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(s.label.substring(0, 1),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: severityColor(s, b),
                        fontWeight: FontWeight.w600)),
              ),
            _h(context, 'Σ', right: true),
          ]),
          for (final s in report.scores)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(t.category(s.category)),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(fmtScore(s.score, lang),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: scoreColor(s.score, b),
                        fontWeight: FontWeight.w600)),
              ),
              for (final sev in Severity.values)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('${s.count(sev)}', textAlign: TextAlign.right),
                ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text('${s.total}', textAlign: TextAlign.right),
              ),
            ]),
        ],
      ),
      if (report.suppressed > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(t.suppressedCount(report.suppressed),
              style: theme.textTheme.bodySmall),
        ),
    ]);
  }

  Widget _h(BuildContext context, String s, {bool right = false}) => Padding(
        padding: const EdgeInsets.all(4),
        child: Text(s,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: Theme.of(context).textTheme.labelMedium),
      );
}
