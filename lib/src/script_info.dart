/// Informations structurelles sur un script : shebang, dialecte, métriques.
library;

import 'embedded.dart';

/// Dialecte déduit du shebang ou de l'extension (ou forcé par l'utilisateur) :
/// un shell, Python 3, un autre langage de script (Perl, Ruby, Lua, Node.js,
/// Dart)
/// ou un fichier de configuration d'administration (unité systemd, crontab,
/// sudoers).
enum Dialect {
  sh,
  bash,
  dash,
  ksh,
  zsh,
  python,
  perl,
  ruby,
  lua,
  node,
  dart,
  systemd,
  crontab,
  sudoers,
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

  /// Script shell (dialecte inconnu compris : les outils shell s'y appliquent).
  bool get isShell => switch (this) {
        Dialect.python ||
        Dialect.perl ||
        Dialect.ruby ||
        Dialect.lua ||
        Dialect.node ||
        Dialect.dart ||
        Dialect.systemd ||
        Dialect.crontab ||
        Dialect.sudoers =>
          false,
        _ => true,
      };

  /// Fichier de configuration d'administration, pas un programme.
  bool get isConfig =>
      this == Dialect.systemd ||
      this == Dialect.crontab ||
      this == Dialect.sudoers;

  /// Nom du langage tel que le désignent les outils et les règles : `shell`
  /// pour tous les shells, sinon le nom du dialecte.
  String get languageName => isShell ? 'shell' : name;

  /// Début d'un commentaire de ligne.
  String get commentPrefix => switch (this) {
        Dialect.lua => '--',
        Dialect.node || Dialect.dart => '//',
        _ => '#',
      };

  /// Extension du fichier temporaire écrit pour les outils externes.
  String get fileExtension => switch (this) {
        Dialect.python => 'py',
        Dialect.perl => 'pl',
        Dialect.ruby => 'rb',
        Dialect.lua => 'lua',
        Dialect.node => 'js',
        Dialect.dart => 'dart',
        Dialect.systemd => 'service',
        Dialect.crontab => 'cron',
        Dialect.sudoers => 'sudoers',
        _ => 'sh',
      };
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

  /// Scripts intégrés à un autre fichier (Dockerfile, CI…) : [content] et
  /// [lines] sont alors le script virtuel analysé, [displayLines] le fichier.
  final EmbeddedScript? embedded;

  const ScriptInfo._(this.path, this.content, this.lines, this.shebang,
      this.dialect, this.hasCrlf,
      [this.embedded]);

  /// Lignes à montrer (extraits, source) : celles du fichier.
  List<String> get displayLines => embedded?.source ?? lines;

  /// Dialecte, suivi du type de fichier hôte pour les scripts intégrés.
  String get dialectLabel => embedded == null
      ? dialect.name
      : '${dialect.name} (${embedded!.kind.label}, ${embedded!.blocks.length})';

  /// [embedded] : false pour lire un fichier hôte (Dockerfile…) comme un
  /// script ordinaire.
  factory ScriptInfo.fromContent(String path, String content,
      {Dialect? forcedDialect, bool embedded = true}) {
    final hasCrlf = content.contains('\r\n');
    final normalized = content.replaceAll('\r\n', '\n');
    final kind = embedded ? detectEmbedded(path, normalized) : null;
    if (kind != null) {
      final e = extractEmbedded(kind, normalized);
      return ScriptInfo._(path, '${e.lines.join('\n')}\n', e.lines, null,
          forcedDialect ?? e.dialect, hasCrlf, e);
    }
    var lines = normalized.split('\n');
    // Un fichier terminé par \n ne compte pas de ligne vide finale.
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }
    final shebang =
        lines.isNotEmpty && lines.first.startsWith('#!') ? lines.first : null;
    var dialect = forcedDialect ?? dialectFromShebang(shebang);
    if (dialect == Dialect.unknown) dialect = dialectFromPath(path);
    return ScriptInfo._(
        path, normalized, List.unmodifiable(lines), shebang, dialect, hasCrlf);
  }

  /// Dialecte déduit du nom du fichier seul ([Dialect.unknown] si le nom ne
  /// dit rien : un shell sans extension, par exemple).
  static Dialect dialectFromPath(String path) {
    final lower = path.toLowerCase().replaceAll('\\', '/');
    final name = lower.split('/').last;
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
    if (isPythonPath(path)) return Dialect.python;
    if (name == 'crontab' || lower.contains('/cron.d/') || ext == '.cron') {
      return Dialect.crontab;
    }
    if (name == 'sudoers' || lower.contains('/sudoers.d/')) {
      return Dialect.sudoers;
    }
    return switch (ext) {
      '.pl' || '.pm' || '.t' => Dialect.perl,
      '.rb' || '.rake' || '.gemspec' => Dialect.ruby,
      '.lua' => Dialect.lua,
      '.js' || '.mjs' || '.cjs' => Dialect.node,
      '.dart' => Dialect.dart,
      '.service' ||
      '.timer' ||
      '.socket' ||
      '.mount' ||
      '.path' ||
      '.target' =>
        Dialect.systemd,
      _ => Dialect.unknown,
    };
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
      _ when RegExp(r'^perl(?:\d+(?:\.\d+)*)?$').hasMatch(interp) =>
        Dialect.perl,
      _ when RegExp(r'^ruby(?:\d+(?:\.\d+)*)?$').hasMatch(interp) =>
        Dialect.ruby,
      _ when RegExp(r'^(?:lua|luajit)[\d.-]*$').hasMatch(interp) => Dialect.lua,
      'node' || 'nodejs' || 'deno' || 'bun' => Dialect.node,
      'dart' => Dialect.dart,
      _ => Dialect.unknown,
    };
  }

  int get totalLines => lines.length;

  /// Lignes de code : ni vides, ni commentaires, shebang exclu ; en Python,
  /// les docstrings (chaînes triples isolées) sont de la documentation.
  int get codeLines => dialect.isPython
      ? _pythonCounts().$1
      : lines.where((l) {
          final t = l.trim();
          return t.isNotEmpty && !_isComment(t);
        }).length;

  /// Lignes de commentaire (et, en Python, de docstring), shebang exclu.
  int get commentLines => dialect.isPython
      ? _pythonCounts().$2
      : lines.skip(shebang == null ? 0 : 1).where((l) {
          return _isComment(l.trim());
        }).length;

  /// Ligne (déjà épurée) de commentaire : préfixe du langage, plus `;` pour
  /// les unités systemd et `*` des blocs `/* … */` de JavaScript.
  bool _isComment(String t) {
    final p = dialect.commentPrefix;
    if (t.startsWith(p)) return true;
    return switch (dialect) {
      Dialect.systemd => t.startsWith(';'),
      Dialect.node || Dialect.dart => t.startsWith('/*') || t.startsWith('*'),
      _ => false,
    };
  }

  static final _docOpen = RegExp(r'''^[rRuUbB]?("\"\"|\'\'\')''');

  /// (lignes de code, lignes de documentation) d'un script Python.
  (int, int) _pythonCounts() {
    var code = 0, doc = 0;
    String? open; // délimiteur d'une docstring ouverte
    String? data; // délimiteur d'une chaîne triple ouverte dans le code
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (i == 0 && shebang != null) continue;
      if (open != null) {
        doc++;
        if (t.contains(open)) open = null;
        continue;
      }
      if (data != null) {
        code++;
        if (t.contains(data)) data = null;
        continue;
      }
      if (t.isEmpty) continue;
      if (t.startsWith('#')) {
        doc++;
        continue;
      }
      final m = _docOpen.firstMatch(t);
      if (m != null) {
        doc++;
        final q = m[1]!;
        // Fermée sur la même ligne ?
        if (!t.substring(m.end).contains(q)) open = q;
        continue;
      }
      code++;
      // Chaîne triple ouverte sur une ligne de code (x = """…) : les lignes
      // suivantes jusqu'à sa fermeture sont des données, donc du code.
      for (final q in const ['"""', "'''"]) {
        if (q.allMatches(t).length.isOdd) data = q;
      }
    }
    return (code, doc);
  }
}
