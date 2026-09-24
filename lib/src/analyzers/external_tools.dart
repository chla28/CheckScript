/// Intégration de shfmt, bashate, checkbashisms et du contrôle syntaxique
/// natif du shell (`bash -n`, `dash -n`…).
library;

import '../config.dart';
import '../model/finding.dart';
import '../script_info.dart';
import 'analyzer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Contrôle syntaxique : <shell> -n
// ─────────────────────────────────────────────────────────────────────────────

class SyntaxAnalyzer extends Analyzer {
  @override
  String get name => 'syntax';

  /// Interpréteur utilisé pour `-n` selon le dialecte.
  static String interpreterFor(Dialect d) => switch (d) {
        Dialect.sh || Dialect.dash => 'sh',
        Dialect.ksh => 'ksh',
        Dialect.zsh => 'zsh',
        _ => 'bash',
      };

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final shell = interpreterFor(ctx.script.dialect);
    final r = await ctx.run(shell, ['-n', ctx.filePath]);
    if (r == null) {
      return AnalyzerResult(
          ToolRun(name, ToolStatus.missing, detail: '$shell -n'));
    }
    final findings =
        r.exitCode == 0 ? <Finding>[] : parseSyntaxErrors(r.stderr);
    if (r.exitCode != 0 && findings.isEmpty) {
      findings.add(Finding(
          tool: name,
          ruleId: 'SYNTAX',
          category: Category.robustness,
          severity: Severity.critical,
          line: 0,
          message: r.stderr.trim().split('\n').first));
    }
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok,
            detail: '$shell -n', findings: findings.length),
        findings);
  }
}

/// Analyse la sortie d'erreur de `bash -n` / `sh -n` / `dash -n`.
///   `f.sh: line 5: syntax error near unexpected token `}'`
///   `f.sh: 5: Syntax error: "}" unexpected`            (dash)
List<Finding> parseSyntaxErrors(String stderr) {
  final re = RegExp(r'^[^:]*:\s*(?:line\s+)?(\d+):\s*(.*)$');
  final out = <Finding>[];
  for (final l in stderr.split('\n')) {
    final m = re.firstMatch(l.trim());
    if (m == null) continue;
    final msg = m.group(2)!.trim();
    // bash répète la ligne fautive entre backticks : on l'ignore.
    if (msg.startsWith('`')) continue;
    out.add(Finding(
      tool: 'syntax',
      ruleId: 'SYNTAX',
      category: Category.robustness,
      severity: Severity.critical,
      line: int.parse(m.group(1)!),
      message: msg,
      equivalents: const ['SC1*', 'E040'],
    ));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// shfmt : écarts de formatage (et erreurs d'analyse)
// ─────────────────────────────────────────────────────────────────────────────

class ShfmtAnalyzer extends Analyzer {
  @override
  String get name => 'shfmt';

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    // Certaines compilations (Fedora) affichent une version vide.
    return r == null ? null : extractVersion(r.stdout) ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final s = ctx.script;
    if (s.dialect == Dialect.zsh) {
      return AnalyzerResult(
          ToolRun(name, ToolStatus.skipped, detail: 'zsh non supporté'));
    }
    // On évalue la cohérence du formatage dans le style d'indentation du
    // script lui-même (espaces ou tabulations) : le choix du style n'est pas
    // un défaut, ses incohérences oui.
    final args = [
      '-d',
      '-ln=${s.dialect.shfmtName ?? 'auto'}',
      '-i=${indentUnit(s.lines)}',
      ctx.filePath,
    ];
    var r = await ctx.run(tc.executable, args);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    var errors = parseShfmtErrors(r.stderr);
    // Script POSIX non analysable en mode POSIX : si le mode bash l'accepte,
    // l'erreur vient de constructions bash (portabilité), pas de la syntaxe.
    if (errors.isNotEmpty && s.dialect.isPosix) {
      final retry = await ctx.run(tc.executable,
          [for (final a in args) a.startsWith('-ln=') ? '-ln=bash' : a]);
      if (retry != null && parseShfmtErrors(retry.stderr).isEmpty) {
        errors = [for (final e in errors) e.asDialectIssue()];
        r = retry;
      }
    }
    final findings = [...parseShfmtDiff(r.stdout), ...errors];
    if (r.exitCode > 1 && findings.isEmpty) {
      return AnalyzerResult(
          ToolRun(name, ToolStatus.failed, detail: r.stderr.trim()));
    }
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok, findings: findings.length), findings);
  }
}

/// Unité d'indentation dominante : 0 pour des tabulations, sinon le plus petit
/// retrait en espaces rencontré (2 par défaut).
int indentUnit(List<String> lines) {
  var tabs = 0, spaces = 0;
  final widths = <int, int>{};
  for (final l in lines) {
    if (l.trim().isEmpty) continue;
    if (l.startsWith('\t')) {
      tabs++;
    } else if (l.startsWith(' ')) {
      spaces++;
      final w = l.length - l.trimLeft().length;
      widths[w] = (widths[w] ?? 0) + 1;
    }
  }
  if (tabs > spaces) return 0;
  if (widths.isEmpty) return 2;
  // Plus petit retrait significatif (≥ 10 % des lignes indentées ou ≥ 2).
  final sorted = widths.keys.toList()..sort();
  for (final w in sorted) {
    if (widths[w]! >= 2 || widths[w]! * 10 >= spaces) return w.clamp(1, 8);
  }
  return sorted.first.clamp(1, 8);
}

/// Un problème par bloc (`@@ -a,b +c,d @@`) du diff produit par `shfmt -d`.
List<Finding> parseShfmtDiff(String diff) {
  final re = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@');
  final out = <Finding>[];
  final lines = diff.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = re.firstMatch(lines[i]);
    if (m == null) continue;
    // Première ligne réellement modifiée dans le bloc.
    var line = int.parse(m.group(1)!);
    var changed = 0;
    var firstChange = 0;
    for (var j = i + 1; j < lines.length && !lines[j].startsWith('@@'); j++) {
      final l = lines[j];
      if (l.startsWith('-')) {
        changed++;
        if (firstChange == 0) firstChange = line;
        line++;
      } else if (l.startsWith(' ')) {
        line++;
      }
    }
    if (changed == 0) continue;
    out.add(Finding(
      tool: 'shfmt',
      ruleId: 'FORMAT',
      category: Category.maintainability,
      severity: Severity.low,
      line: firstChange,
      message: 'Formatting differs from shfmt canonical style '
          '($changed line(s) to reformat)',
    ));
  }
  return out;
}

extension on Finding {
  /// Requalifie une erreur d'analyse shfmt en problème de dialecte.
  Finding asDialectIssue() => Finding(
        tool: tool,
        ruleId: 'DIALECT',
        category: Category.portability,
        severity: Severity.medium,
        line: line,
        column: column,
        message: message,
        equivalents: _dialectEquivalents,
      );
}

const _dialectEquivalents = ['SC3*', 'SC2039', 'SC2112', 'SC2113', 'CB'];

/// Erreurs d'analyse de shfmt : `f.sh:3:14: the "function" builtin is a bash
/// feature; tried parsing as posix`.
List<Finding> parseShfmtErrors(String stderr) {
  final re = RegExp(r'^.*?:(\d+):(\d+):\s*(.*)$');
  final out = <Finding>[];
  for (final l in stderr.split('\n')) {
    final m = re.firstMatch(l.trim());
    if (m == null) continue;
    final msg = m.group(3)!;
    final dialectIssue = RegExp(r'bash feature|mksh feature|parsing as posix|'
            r'posix feature|not supported')
        .hasMatch(msg);
    out.add(Finding(
      tool: 'shfmt',
      ruleId: dialectIssue ? 'DIALECT' : 'PARSE',
      category: dialectIssue ? Category.portability : Category.robustness,
      severity: dialectIssue ? Severity.medium : Severity.high,
      line: int.parse(m.group(1)!),
      column: int.parse(m.group(2)!),
      message: msg,
      equivalents:
          dialectIssue ? _dialectEquivalents : const ['SYNTAX', 'SC1*'],
    ));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// bashate : style (conventions OpenStack)
// ─────────────────────────────────────────────────────────────────────────────

class BashateAnalyzer extends Analyzer {
  @override
  String get name => 'bashate';

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    return r == null ? null : extractVersion('${r.stdout}${r.stderr}') ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    // E003 (indentation multiple de 4) est ignoré quand le script est indenté
    // autrement : shfmt contrôle déjà la cohérence de l'indentation.
    final ignore = [
      ...tc.exclude,
      if (indentUnit(ctx.script.lines) != 4) 'E003',
    ];
    final args = [
      if (ignore.isNotEmpty) '--ignore=${ignore.join(',')}',
      '--max-line-length=${ctx.config.thresholds.maxLineLength}',
      ctx.filePath,
    ];
    final r = await ctx.run(tc.executable, args);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    final findings = parseBashate('${r.stdout}\n${r.stderr}');
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok, findings: findings.length), findings);
  }
}

/// Classement des codes bashate (les autres : Maintenabilité / Low).
const Map<String, (Category, Severity)> bashateMap = {
  'E040': (Category.robustness, Severity.high), // erreur de syntaxe
  'E042': (Category.robustness, Severity.low), // local masque les erreurs
  'E043': (Category.robustness, Severity.low), // (( )) : code de retour
  'E044': (Category.robustness, Severity.low), // [[ ]] pour =~ < >
  'E041': (Category.portability, Severity.low), // $[ ] obsolète
  'E020': (Category.maintainability, Severity.low),
};

/// Formats pris en charge :
///   bashate ≥ 2 : `f.sh:4:1: E003 Indent not multiple of 4`
///   bashate 0.x : `[E] E003: Indent not multiple of 4: '  x'` puis ` - f.sh : L4`
///
/// bashate indique toujours la colonne 1, quel que soit le défaut : la
/// colonne est donc tenue pour inconnue (0).
List<Finding> parseBashate(String output) {
  final modern = RegExp(r'^.*?:(\d+):(\d+):\s*([EW]\d{3})\s+(.*)$');
  final legacy = RegExp(r'^\[[EW]\]\s*([EW]\d{3}):\s*(.*)$');
  final legacyLoc = RegExp(r'^\s*-\s*.*:\s*L(\d+)\s*$');
  final out = <Finding>[];
  final lines = output.split('\n');
  Finding make(String code, int line, String msg) {
    final m = bashateMap[code];
    return Finding(
      tool: 'bashate',
      ruleId: code,
      category: m?.$1 ?? Category.maintainability,
      severity: m?.$2 ?? Severity.low,
      line: line,
      message: msg.trim(),
      equivalents: code == 'E040' ? const ['SYNTAX', 'SC1*'] : const [],
    );
  }

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    final m = modern.firstMatch(l);
    if (m != null) {
      out.add(make(m.group(3)!, int.parse(m.group(1)!), m.group(4)!));
      continue;
    }
    final g = legacy.firstMatch(l);
    if (g != null) {
      var line = 0;
      if (i + 1 < lines.length) {
        final loc = legacyLoc.firstMatch(lines[i + 1]);
        if (loc != null) {
          line = int.parse(loc.group(1)!);
          i++;
        }
      }
      out.add(make(g.group(1)!, line, g.group(2)!));
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// checkbashisms : bashismes dans les scripts /bin/sh
// ─────────────────────────────────────────────────────────────────────────────

class CheckbashismsAnalyzer extends Analyzer {
  @override
  String get name => 'checkbashisms';

  @override
  Future<String?> version(CommandRunner runner, CheckConfig config) async {
    final r = await runner.run(config.tool(name).executable, ['--version']);
    if (r == null) return null;
    return extractVersion(r.stdout) ?? '?';
  }

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final tc = ctx.config.tool(name);
    final d = ctx.script.dialect;
    // Les bashismes ne sont des défauts que pour un script censé être POSIX
    // (ou sans shebang : l'interpréteur réel est alors inconnu).
    if (!d.isPosix && d != Dialect.unknown) {
      return AnalyzerResult(
          ToolRun(name, ToolStatus.skipped, detail: 'dialecte ${d.name}'));
    }
    final args = ['--extra', if (d == Dialect.unknown) '--force', ctx.filePath];
    final r = await ctx.run(tc.executable, args);
    if (r == null) return AnalyzerResult(ToolRun(name, ToolStatus.missing));
    final findings = parseCheckbashisms(r.stderr.isEmpty ? r.stdout : r.stderr);
    return AnalyzerResult(
        ToolRun(name, ToolStatus.ok, findings: findings.length), findings);
  }
}

/// `possible bashism in f.sh line 6 (should be 'b = a'):` puis la ligne de code.
List<Finding> parseCheckbashisms(String output) {
  final re = RegExp(r'^possible bashism in .* line (\d+) \((.*)\):\s*$');
  final out = <Finding>[];
  final lines = output.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = re.firstMatch(lines[i]);
    if (m == null) continue;
    final snippet =
        i + 1 < lines.length && !lines[i + 1].startsWith('possible bashism')
            ? lines[i + 1].trim()
            : null;
    out.add(Finding(
      tool: 'checkbashisms',
      ruleId: 'CB',
      category: Category.portability,
      severity: Severity.medium,
      line: int.parse(m.group(1)!),
      message: 'Possible bashism: ${m.group(2)}',
      snippet: snippet,
      equivalents: const [
        'SC3*',
        'SC2039',
        'SC2112',
        'SC2113',
        'DIALECT',
        'POR003'
      ],
    ));
  }
  return out;
}
