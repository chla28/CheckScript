/// Police et couleurs du code (source, diff, exemples de correction).
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';

/// Police embarquée (JetBrains Mono, variante sans ligatures).
const defaultCodeFont = 'JetBrains Mono';

/// Taille par défaut et bornes de la police du code (points).
const defaultCodeFontSize = 13.0;
const minCodeFontSize = 8.0;
const maxCodeFontSize = 32.0;

/// Style du code : police choisie (repli sur la police embarquée puis sur
/// celles du système), taille, hauteur de ligne fixe.
TextStyle codeTextStyle(String? family, double size, {Color? color}) =>
    TextStyle(
      fontFamily: family ?? defaultCodeFont,
      fontFamilyFallback: const [
        defaultCodeFont,
        'DejaVu Sans Mono',
        'Liberation Mono',
        'monospace',
      ],
      fontSize: size,
      height: codeLineHeight(size) / size,
      color: color,
    );

/// Hauteur d'une ligne de code pour une taille de police.
double codeLineHeight(double size) => (size * 1.54).roundToDouble();

/// Polices à chasse fixe installées (fontconfig), triées ; vide si
/// `fc-list` est absent.
Future<List<String>> installedMonospaceFonts() async {
  try {
    final r = await Process.run('fc-list', [':spacing=mono', 'family']);
    if (r.exitCode != 0) return const [];
    final names = <String>{
      for (final l in '${r.stdout}'.split('\n'))
        if (l.trim().isNotEmpty) l.split(',').first.trim(),
    };
    return names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } on ProcessException {
    return const [];
  }
}

/// Couleur d'un jeton selon le thème (palettes inspirées de GitHub).
Color tokenColor(TokenKind k, Brightness b) {
  final dark = b == Brightness.dark;
  return switch (k) {
    TokenKind.comment =>
      dark ? const Color(0xFF8B949E) : const Color(0xFF6E7781),
    TokenKind.string =>
      dark ? const Color(0xFFA5D6FF) : const Color(0xFF0A3069),
    TokenKind.keyword =>
      dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E),
    TokenKind.builtin =>
      dark ? const Color(0xFFD2A8FF) : const Color(0xFF8250DF),
    TokenKind.variable =>
      dark ? const Color(0xFFFFA657) : const Color(0xFF953800),
    TokenKind.number =>
      dark ? const Color(0xFF79C0FF) : const Color(0xFF0550AE),
    TokenKind.operator =>
      dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E),
    TokenKind.function =>
      dark ? const Color(0xFFD2A8FF) : const Color(0xFF8250DF),
    TokenKind.key => dark ? const Color(0xFF7EE787) : const Color(0xFF116329),
    TokenKind.shebang =>
      dark ? const Color(0xFF8B949E) : const Color(0xFF6E7781),
  };
}

/// Ligne colorée : texte ordinaire entre les jetons.
TextSpan highlightedLine(
    String line, List<Token> tokens, TextStyle base, Brightness b) {
  final spans = <TextSpan>[];
  var pos = 0;
  for (final t in tokens) {
    if (t.start > pos) spans.add(TextSpan(text: line.substring(pos, t.start)));
    spans.add(TextSpan(
      text: line.substring(t.start, t.end),
      style: TextStyle(
        color: tokenColor(t.kind, b),
        fontStyle: t.kind == TokenKind.comment || t.kind == TokenKind.shebang
            ? FontStyle.italic
            : null,
        fontWeight: t.kind == TokenKind.keyword || t.kind == TokenKind.key
            ? FontWeight.bold
            : null,
      ),
    ));
    pos = t.end;
  }
  if (pos < line.length) spans.add(TextSpan(text: line.substring(pos)));
  return TextSpan(style: base, children: spans);
}

/// Police et taille du code choisies dans les réglages, pour tous les blocs
/// de code de l'interface (source, diff, corrections).
class CodeFont extends InheritedWidget {
  const CodeFont(
      {super.key, this.family, required this.size, required super.child});

  final String? family;
  final double size;

  static CodeFont? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CodeFont>();

  /// Style du code dans ce contexte (réglages par défaut sans [CodeFont]).
  static TextStyle styleOf(BuildContext context, {Color? color}) {
    final f = maybeOf(context);
    return codeTextStyle(f?.family, f?.size ?? defaultCodeFontSize,
        color: color);
  }

  @override
  bool updateShouldNotify(CodeFont old) =>
      old.family != family || old.size != size;
}
