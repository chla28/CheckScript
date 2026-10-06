/// Source annotée : numéros de ligne, marque de sévérité en marge, ligne
/// sélectionnée mise en évidence, coloration syntaxique ; défilement
/// jusqu'à une ligne donnée ; Ctrl+molette change la taille du texte.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../code_style.dart';
import 'common.dart';

class SourceView extends StatefulWidget {
  const SourceView({
    super.key,
    required this.lines,
    required this.findings,
    this.selectedLine,
    this.onLineTap,
    this.language,
    this.fontFamily,
    this.fontSize = defaultCodeFontSize,
    this.onZoom,
    this.header,
    this.matchLines = const {},
  });

  final List<String> lines;
  final List<Finding> findings;
  final int? selectedLine;
  final void Function(int line)? onLineTap;

  /// Langage de la coloration (null : pas de coloration).
  final HighlightLanguage? language;

  /// Police (null : police embarquée) et taille du code.
  final String? fontFamily;
  final double fontSize;

  /// Ctrl+molette : +1 ou -1 point.
  final void Function(double delta)? onZoom;

  /// Barre affichée au-dessus du code (taille du texte…).
  final Widget? header;

  /// Lignes (numéros à partir de 1) contenant le texte cherché : teintées.
  final Set<int> matchLines;

  @override
  State<SourceView> createState() => _SourceViewState();
}

class _SourceViewState extends State<SourceView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  /// Jetons calculés pour ces lignes et ce langage.
  List<List<Token>>? _tokens;
  (List<String>, HighlightLanguage?)? _tokensFor;

  double get _lineHeight => codeLineHeight(widget.fontSize);

  List<List<Token>>? _highlight() {
    final lang = widget.language;
    if (lang == null) return null;
    final key = _tokensFor;
    if (key == null || !identical(key.$1, widget.lines) || key.$2 != lang) {
      _tokens = highlightLines(widget.lines, lang);
      _tokensFor = (widget.lines, lang);
    }
    return _tokens;
  }

  @override
  void didUpdateWidget(SourceView old) {
    super.didUpdateWidget(old);
    final l = widget.selectedLine;
    if (l != null && l != old.selectedLine && l > 0 && _vertical.hasClients) {
      final target = ((l - 5) * _lineHeight)
          .clamp(0.0, _vertical.position.maxScrollExtent);
      _vertical.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Ctrl+molette : taille du texte (la molette seule fait défiler).
  void _zoomSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(
          e, (_) => widget.onZoom?.call(e.scrollDelta.dy < 0 ? 1 : -1));
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
    final mono = codeTextStyle(widget.fontFamily, widget.fontSize,
        color: theme.colorScheme.onSurface);
    final digits = '${widget.lines.length}'.length;
    final tokens = _highlight();
    // Largeur d'un chiffre, pour la colonne des numéros de ligne.
    final digitWidth = (TextPainter(
            text: TextSpan(text: '0', style: mono),
            textDirection: TextDirection.ltr)
          ..layout())
        .width;

    final list = Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Scrollbar(
        controller: _vertical,
        child: ListView.builder(
          controller: _vertical,
          itemExtent: _lineHeight,
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
                    : (widget.matchLines.contains(n)
                        ? Colors.amber.withValues(alpha: 0.28)
                        : null),
                child: Row(children: [
                  Container(
                      width: 4,
                      color: sev == null
                          ? Colors.transparent
                          : severityColor(sev, b)),
                  SizedBox(
                    width: 12.0 + digits * digitWidth,
                    child: Text('$n',
                        textAlign: TextAlign.right,
                        style: mono.copyWith(color: theme.disabledColor)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: tokens == null
                        ? Text(widget.lines[i],
                            style: mono,
                            softWrap: false,
                            overflow: TextOverflow.fade)
                        : Text.rich(
                            highlightedLine(
                                widget.lines[i], tokens[i], mono, b),
                            softWrap: false,
                            overflow: TextOverflow.fade),
                  ),
                ]),
              ),
            );
            final shown = sev == null
                ? row
                : Tooltip(
                    message: tips[n]!.join('\n'),
                    waitDuration: const Duration(milliseconds: 400),
                    child: row);
            // Sur chaque ligne : l'écouteur passe avant la liste défilante,
            // qui prendrait sinon la molette pour elle.
            return widget.onZoom == null
                ? shown
                : Listener(onPointerSignal: _zoomSignal, child: shown);
          },
        ),
      ),
    );
    // Sous la dernière ligne (script court) aussi.
    final zoomable = widget.onZoom == null
        ? list
        : Listener(onPointerSignal: _zoomSignal, child: list);
    final header = widget.header;
    return header == null
        ? zoomable
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            Expanded(child: zoomable),
          ]);
  }
}
