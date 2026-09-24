/// Informations structurelles sur un script : shebang, dialecte, métriques.
library;

/// Dialecte déduit du shebang ou de l'extension (ou forcé par l'utilisateur) :
/// un shell, ou Python 3.
enum Dialect {
  sh,
  bash,
  dash,
  ksh,
  zsh,
  python,
  unknown;

  static Dialect? tryParse(String s) {
    for (final d in values) {
      if (d.name == s.toLowerCase()) return d;
    }
    return null;
  }

  /// Valeur passée à `shellcheck --shell=` (null : laisser shellcheck décider).
  String? get shellcheckName => switch (this) {
        Dialect.sh => 'sh',
        Dialect.bash => 'bash',
        Dialect.dash => 'dash',
        Dialect.ksh => 'ksh',
        _ => null,
      };

  /// Valeur passée à `shfmt -ln=` (null : `auto`).
  String? get shfmtName => switch (this) {
        Dialect.sh || Dialect.dash => 'posix',
        Dialect.bash => 'bash',
        Dialect.ksh => 'mksh',
        _ => null,
      };

  /// Script censé être POSIX (les bashismes y sont des défauts de portabilité).
  bool get isPosix => this == Dialect.sh || this == Dialect.dash;

  /// Script Python (analysé par les outils Python, pas par les outils shell).
  bool get isPython => this == Dialect.python;
}

class ScriptInfo {
  final String path;
  final String content;
  final List<String> lines;

  /// Première ligne si elle commence par `#!`, sinon null.
  final String? shebang;
  final Dialect dialect;

  /// Le fichier d'origine contient des fins de ligne Windows (CRLF).
  final bool hasCrlf;

  const ScriptInfo._(this.path, this.content, this.lines, this.shebang,
      this.dialect, this.hasCrlf);

  factory ScriptInfo.fromContent(String path, String content,
      {Dialect? forcedDialect}) {
    final hasCrlf = content.contains('\r\n');
    final normalized = content.replaceAll('\r\n', '\n');
    var lines = normalized.split('\n');
    // Un fichier terminé par \n ne compte pas de ligne vide finale.
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }
    final shebang =
        lines.isNotEmpty && lines.first.startsWith('#!') ? lines.first : null;
    var dialect = forcedDialect ?? dialectFromShebang(shebang);
    if (dialect == Dialect.unknown && isPythonPath(path)) {
      dialect = Dialect.python;
    }
    return ScriptInfo._(
        path, normalized, List.unmodifiable(lines), shebang, dialect, hasCrlf);
  }

  /// Extension d'un script Python (`.py`, `.pyw`).
  static bool isPythonPath(String path) =>
      RegExp(r'\.pyw?$', caseSensitive: false).hasMatch(path);

  /// Déduit le dialecte d'une ligne `#!` (`#!/bin/bash`, `#!/usr/bin/env -S bash -e`…).
  static Dialect dialectFromShebang(String? shebang) {
    if (shebang == null) return Dialect.unknown;
    final parts = shebang.substring(2).trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return Dialect.unknown;
    var interp = parts.first.split('/').last;
    if (interp == 'env') {
      interp = parts
          .skip(1)
          .firstWhere((p) => !p.startsWith('-'), orElse: () => '')
          .split('/')
          .last;
    }
    return switch (interp) {
      'sh' => Dialect.sh,
      'bash' => Dialect.bash,
      'dash' => Dialect.dash,
      'ksh' || 'mksh' || 'ksh93' => Dialect.ksh,
      'zsh' => Dialect.zsh,
      _ when RegExp(r'^python(?:[23](?:\.\d+)?)?$').hasMatch(interp) =>
        Dialect.python,
      _ => Dialect.unknown,
    };
  }

  int get totalLines => lines.length;

  /// Lignes de code : ni vides, ni commentaires, shebang exclu.
  int get codeLines => lines.where((l) {
        final t = l.trim();
        return t.isNotEmpty && !t.startsWith('#');
      }).length;

  int get commentLines => lines.skip(shebang == null ? 0 : 1).where((l) {
        return l.trim().startsWith('#');
      }).length;
}
