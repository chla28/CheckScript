/// Courbe de la note moyenne d'un dossier au fil des analyses.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';

import '../history.dart';
import 'common.dart';

class HistoryChart extends StatelessWidget {
  const HistoryChart({super.key, required this.entries, required this.lang});

  final List<HistoryEntry> entries;
  final Lang lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: HistoryPainter(
        [for (final e in entries) e.average],
        line: theme.colorScheme.primary,
        grid: theme.colorScheme.outlineVariant,
        text: theme.textTheme.labelSmall!,
        pointColor: (v) => scoreColor(v, theme.brightness),
        first: _date(entries.first.date),
        last: _date(entries.last.date),
      ),
      child: const SizedBox.expand(),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Dessin : axe 0-10 (repères 4, 6, 7,5, 9 : seuils des niveaux), une
/// courbe et un point coloré par analyse, dates de la première et de la
/// dernière.
class HistoryPainter extends CustomPainter {
  HistoryPainter(this.values,
      {required this.line,
      required this.grid,
      required this.text,
      required this.pointColor,
      required this.first,
      required this.last});

  final List<double> values;
  final Color line, grid;
  final TextStyle text;
  final Color Function(double) pointColor;
  final String first, last;

  static const left = 28.0, bottom = 18.0, top = 6.0;

  /// Position d'une analyse (indice [i] sur [n]) de note [v] dans [size].
  static Offset point(Size size, int i, int n, double v) {
    final w = size.width - left - 8;
    final h = size.height - bottom - top;
    final x = left + (n <= 1 ? w / 2 : w * i / (n - 1));
    return Offset(x, top + h * (1 - v.clamp(0, 10) / 10));
  }

  void _label(Canvas c, String s, Offset at, {bool right = false}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: text), textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, at - Offset(right ? tp.width : 0, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0.0, 4.0, 6.0, 7.5, 9.0, 10.0]) {
      final y = point(size, 0, 1, v).dy;
      canvas.drawLine(Offset(left, y), Offset(size.width - 8, y), g);
      _label(canvas, fmtScore(v, Lang.fr), Offset(left - 4, y), right: true);
    }
    if (values.isEmpty) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = point(size, i, values.length, values[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(size, i, values.length, values[i]), 3.5,
          Paint()..color = pointColor(values[i]));
    }
    final by = size.height - bottom / 2;
    _label(canvas, first, Offset(left, by));
    _label(canvas, last, Offset(size.width - 8, by), right: true);
  }

  @override
  bool shouldRepaint(HistoryPainter old) =>
      old.values != values || old.line != line;
}
