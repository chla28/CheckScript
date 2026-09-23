/// Graphique radar des cinq notes (0–10), avec la référence en pointillés.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadarChart extends StatelessWidget {
  const RadarChart({
    super.key,
    required this.labels,
    required this.values,
    this.previous,
    required this.color,
  });

  final List<String> labels;

  /// Valeurs 0–10, dans l'ordre de [labels].
  final List<double> values;

  /// Valeurs de la référence (facultatif).
  final List<double>? previous;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: [
        for (var i = 0; i < labels.length; i++)
          '${labels[i]} ${values[i].toStringAsFixed(1)}'
      ].join(', '),
      child: CustomPaint(
        painter: RadarPainter(
          labels: labels,
          values: values,
          previous: previous,
          color: color,
          gridColor: theme.dividerColor,
          textStyle:
              theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.labels,
    required this.values,
    required this.color,
    required this.gridColor,
    required this.textStyle,
    this.previous,
  }) : assert(labels.length == values.length && labels.length >= 3);

  final List<String> labels;
  final List<double> values;
  final List<double>? previous;
  final Color color;
  final Color gridColor;
  final TextStyle textStyle;

  /// Point du sommet [i] pour une valeur [v] (0–10).
  static Offset vertex(Offset center, double radius, int i, int n, double v) {
    final angle = -math.pi / 2 + 2 * math.pi * i / n;
    final r = radius * (v.clamp(0, 10) / 10);
    return center + Offset(math.cos(angle) * r, math.sin(angle) * r);
  }

  Path _polygon(Offset c, double radius, List<double> vals) {
    final p = Path();
    for (var i = 0; i < vals.length; i++) {
      final pt = vertex(c, radius, i, vals.length, vals[i]);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 28;
    if (radius <= 0) return;

    final grid = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final level in [2.5, 5.0, 7.5, 10.0]) {
      canvas.drawPath(_polygon(center, radius, List.filled(n, level)), grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, vertex(center, radius, i, n, 10), grid);
    }

    if (previous != null) {
      final prev = Paint()
        ..color = gridColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(_polygon(center, radius, previous!), prev);
    }

    final path = _polygon(center, radius, values);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(
          vertex(center, radius, i, n, values[i]), 3, Paint()..color = color);
    }

    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      final pos = vertex(center, radius + 16, i, n, 10);
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.values != values || old.previous != previous || old.color != color;
}
