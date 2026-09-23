/// Couleurs et petits composants partagés.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';

Color severityColor(Severity s, Brightness b) {
  final dark = b == Brightness.dark;
  return switch (s) {
    Severity.critical =>
      dark ? const Color(0xFFFF6B6B) : const Color(0xFFB3261E),
    Severity.high => dark ? const Color(0xFFFF922B) : const Color(0xFFD9480F),
    Severity.medium => dark ? const Color(0xFFFFD43B) : const Color(0xFFB8860B),
    Severity.low => dark ? const Color(0xFF74C0FC) : const Color(0xFF2F6FB5),
  };
}

Color scoreColor(double v, Brightness b) {
  final dark = b == Brightness.dark;
  if (v >= 7.5) return dark ? const Color(0xFF69DB7C) : const Color(0xFF2E7D32);
  if (v >= 5) return dark ? const Color(0xFFFFD43B) : const Color(0xFFB8860B);
  return dark ? const Color(0xFFFF6B6B) : const Color(0xFFB3261E);
}

String categoryShort(Category c, Lang lang) {
  final full = Messages(lang).category(c);
  return full.length <= 5 ? full : full.substring(0, 4);
}

class SeverityBadge extends StatelessWidget {
  const SeverityBadge(this.severity, {super.key});
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final c = severityColor(severity, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(severity.label,
          style:
              TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Écart de note signé et coloré (tendance par rapport à la référence).
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.now, this.before, this.lang, {super.key});
  final double now;
  final double before;
  final Lang lang;

  @override
  Widget build(BuildContext context) {
    final d = ((now - before) * 10).round() / 10;
    final b = Theme.of(context).brightness;
    final color = d > 0
        ? scoreColor(10, b)
        : (d < 0 ? scoreColor(0, b) : Theme.of(context).disabledColor);
    final icon = d > 0
        ? Icons.trending_up
        : (d < 0 ? Icons.trending_down : Icons.trending_flat);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 2),
      Text(fmtDelta(now, before, lang),
          style: TextStyle(color: color, fontSize: 12)),
    ]);
  }
}
