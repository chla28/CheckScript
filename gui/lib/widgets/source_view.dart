/// Source annotée : numéros de ligne, marque de sévérité en marge, ligne
/// sélectionnée mise en évidence ; défilement jusqu'à une ligne donnée.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';

import 'common.dart';

class SourceView extends StatefulWidget {
  const SourceView({
    super.key,
    required this.lines,
    required this.findings,
    this.selectedLine,
    this.onLineTap,
  });

  final List<String> lines;
  final List<Finding> findings;
  final int? selectedLine;
  final void Function(int line)? onLineTap;

  static const lineHeight = 20.0;

  @override
  State<SourceView> createState() => _SourceViewState();
}

class _SourceViewState extends State<SourceView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void didUpdateWidget(SourceView old) {
    super.didUpdateWidget(old);
    final l = widget.selectedLine;
    if (l != null && l != old.selectedLine && l > 0 && _vertical.hasClients) {
      final target = ((l - 5) * SourceView.lineHeight)
          .clamp(0.0, _vertical.position.maxScrollExtent);
      _vertical.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final worst = <int, Severity>{};
    final tips = <int, List<String>>{};
    for (final f in widget.findings) {
      if (f.line < 1) continue;
      final w = worst[f.line];
      if (w == null || f.severity.index < w.index) worst[f.line] = f.severity;
      (tips[f.line] ??= []).add('${f.ruleId} — ${f.message}');
    }
    final mono = TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['DejaVu Sans Mono', 'Liberation Mono'],
        fontSize: 13,
        height: SourceView.lineHeight / 13,
        color: theme.colorScheme.onSurface);
    final digits = '${widget.lines.length}'.length;

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Scrollbar(
        controller: _vertical,
        child: ListView.builder(
          controller: _vertical,
          itemExtent: SourceView.lineHeight,
          itemCount: widget.lines.length,
          itemBuilder: (context, i) {
            final n = i + 1;
            final sev = worst[n];
            final selected = n == widget.selectedLine;
            final row = InkWell(
              onTap:
                  widget.onLineTap == null ? null : () => widget.onLineTap!(n),
              child: Container(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                    : null,
                child: Row(children: [
                  Container(
                      width: 4,
                      color: sev == null
                          ? Colors.transparent
                          : severityColor(sev, b)),
                  SizedBox(
                    width: 12.0 + digits * 9,
                    child: Text('$n',
                        textAlign: TextAlign.right,
                        style: mono.copyWith(color: theme.disabledColor)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.lines[i],
                        style: mono,
                        softWrap: false,
                        overflow: TextOverflow.fade),
                  ),
                ]),
              ),
            );
            return sev == null
                ? row
                : Tooltip(
                    message: tips[n]!.join('\n'),
                    waitDuration: const Duration(milliseconds: 400),
                    child: row);
          },
        ),
      ),
    );
  }
}
