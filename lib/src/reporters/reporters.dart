/// Mise en forme des rapports : terminal (ANSI), Markdown, AsciiDoc, JSON,
/// SARIF et HTML.
library;

import 'dart:convert';

import '../explain.dart';
import '../i18n.dart';
import 'codeclimate.dart';
import 'html.dart';
import 'sarif.dart';
import '../model/finding.dart';
import '../model/report.dart';
import '../version.dart';

enum OutputFormat {
  terminal,
  markdown,
  asciidoc,
  json,
  sarif,
  html,
  codeclimate;

  /// Format déduit de l'extension d'un fichier de sortie.
  static OutputFormat? fromPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.md') || p.endsWith('.markdown')) return markdown;
    if (p.endsWith('.adoc') || p.endsWith('.asciidoc')) return asciidoc;
    if (p.endsWith('.sarif') || p.endsWith('.sarif.json')) return sarif;
    if (p.endsWith('.codeclimate.json') ||
        p.endsWith('gl-code-quality-report.json')) {
      return codeclimate;
    }
    if (p.endsWith('.json')) return json;
    if (p.endsWith('.html') || p.endsWith('.htm')) return html;
    if (p.endsWith('.txt')) return terminal;
    return null;
  }

  static OutputFormat? tryParse(String s) => switch (s.toLowerCase()) {
        'md' || 'markdown' => markdown,
        'adoc' || 'asciidoc' => asciidoc,
        'json' => json,
        'sarif' => sarif,
        'codeclimate' || 'gitlab' => codeclimate,
        'html' || 'htm' => html,
        'text' || 'txt' || 'terminal' => terminal,
        _ => null,
      };
}

class RenderOptions {
  final Lang lang;
  final bool color;

  /// Nombre maximal de problèmes listés par catégorie (null : tous ; 0 :
  /// synthèse seule). Ne concerne que la sortie terminal.
  final int? maxDetails;

  /// Affiche sous chaque problème la ligne de code concernée (terminal).
  final bool showSource;

  /// Terminal : détail du coût de chaque règle (`--explain`).
  final bool explain;

  /// Terminal : problèmes triés par gain rapide plutôt que par catégorie.
  final bool byQuickWin;

  const RenderOptions(
      {this.lang = Lang.fr,
      this.color = false,
      this.maxDetails,
      this.showSource = true,
      this.explain = false,
      this.byQuickWin = false});
}

String render(
        List<ScriptReport> reports, OutputFormat format, RenderOptions opts) =>
    switch (format) {
      OutputFormat.terminal => renderTerminal(reports, opts),
      OutputFormat.markdown => renderMarkdown(reports, opts),
      OutputFormat.asciidoc => renderAsciidoc(reports, opts),
      OutputFormat.json => renderJson(reports),
      OutputFormat.sarif => renderSarif(reports),
      OutputFormat.html => renderHtml(reports, opts),
      OutputFormat.codeclimate => renderCodeClimate(reports),
    };

// ─────────────────────────────────────────────────────────────────────────────
// Utilitaires communs
// ─────────────────────────────────────────────────────────────────────────────

String fmtScore(double v, Lang lang) {
  final s = v.toStringAsFixed(1);
  return lang == Lang.fr ? s.replaceAll('.', ',') : s;
}

String _date(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
String _two(int v) => v.toString().padLeft(2, '0');

String _toolsLine(ScriptReport r, Messages t) => [
      for (final run in r.tools)
        '${run.tool}${run.version != null ? ' ${run.version}' : ''} '
            '(${t.toolStatus(run.status)})'
    ].join(', ');

/// « Niveau B (7,6) en corrigeant : SC2164, ROB001 », ou null.
String? planLine(ScriptReport r, Messages t, Lang lang) {
  final e = r.explanation;
  if (e.plan.isEmpty || e.nextGrade == null) return null;
  return t.nextGradeLine(e.nextGrade!, fmtScore(e.planScore!, lang),
      e.plan.map((i) => i.ruleId).join(', '));
}

/// Outils dont l'absence est signalée (gitleaks et trufflehog sont des
/// compléments facultatifs, couverts par les règles SEC002/SEC022 ; semgrep,
/// pylint et pyright aussi).
const coreTools = {
  'shellcheck', 'shfmt', 'bashate', 'checkbashisms', 'syntax', //
  'ruff', 'bandit', 'mypy', 'radon', 'vermin',
};

List<String> _missing(List<ScriptReport> reports) => {
      for (final r in reports)
        for (final t in r.tools)
          if (t.status == ToolStatus.missing && coreTools.contains(t.tool))
            t.tool
    }.toList();

String _loc(Finding f, Messages t) => f.line == 0 ? t.wholeFile : '${f.line}';

/// Problèmes à détailler : les nouveaux seulement s'il y a une référence.
List<Finding> detailFindings(ScriptReport r, [Category? c]) {
  final fs = r.comparison?.added ?? r.findings;
  return c == null
      ? fs
      : [
          for (final f in fs)
            if (f.category == c) f
        ];
}

/// Ligne « profil / contexte » (vide pour le profil standard sans contexte).
String? _profileLine(ScriptReport r, Messages t) {
  if (r.profile == 'standard' && r.contexts.isEmpty) return null;
  return '${t.profile}${t.colon}${r.profile}'
      '${r.contexts.isEmpty ? '' : ' · ${t.contexts}${t.colon}${r.contexts.join(', ')}'}';
}

/// Écart signé, ex. « +1,5 » / « -0,3 ».
String fmtDelta(double now, double before, Lang lang) {
  final d = ((now - before) * 10).round() / 10;
  return '${d >= 0 ? '+' : ''}${fmtScore(d, lang)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Terminal
// ─────────────────────────────────────────────────────────────────────────────

class _Ansi {
  final bool on;
  const _Ansi(this.on);
  String _w(String code, String s) => on ? '\x1B[${code}m$s\x1B[0m' : s;
  String bold(String s) => _w('1', s);
  String dim(String s) => _w('2', s);
  String red(String s) => _w('31', s);
  String green(String s) => _w('32', s);
  String yellow(String s) => _w('33', s);
  String blue(String s) => _w('34', s);
  String magenta(String s) => _w('35', s);

  String severity(Severity s, String text) => switch (s) {
        Severity.critical => _w('1;31', text),
        Severity.high => red(text),
        Severity.medium => yellow(text),
        Severity.low => blue(text),
      };

  String score(double v, String text) =>
      v >= 7.5 ? green(text) : (v >= 5 ? yellow(text) : red(text));
}

/// Remplit à droite en tenant compte de la largeur visible (hors ANSI).
String _pad(String s, int width, {bool left = false}) {
  final visible = s.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').runes.length;
  final fill = ' ' * (width - visible).clamp(0, width);
  return left ? '$fill$s' : '$s$fill';
}

String _bar(double score) {
  final n = score.round().clamp(0, 10);
  return '${'█' * n}${'░' * (10 - n)}';
}

/// Largeur maximale de code affichée sous un problème.
const _sourceWidth = 100;

/// Ligne de code d'un problème, avec un repère « ^ » sous la colonne
/// signalée. L'indentation est retirée et une ligne trop longue est cadrée
/// autour de la colonne.
void _writeSource(StringBuffer b, Finding f, _Ansi a, Messages t) {
  final gutter = '    ${_pad('${f.line}', 5, left: true)} │ ';
  final blank = '${' ' * (gutter.length - 2)}│ ';
  final src = f.snippet;
  if (src == null) {
    b.writeln(a.dim('$gutter${t.maskedSecret}'));
    return;
  }
  final indent = src.length - src.trimLeft().length;
  var code = src.substring(indent).replaceAll('\t', ' ');
  var col = f.column > 0 ? f.column - 1 - indent : -1;
  var start = 0;
  if (code.length > _sourceWidth) {
    if (col >= _sourceWidth - 10) start = col - _sourceWidth ~/ 2;
    final end = (start + _sourceWidth).clamp(0, code.length);
    code = '${start > 0 ? '…' : ''}${code.substring(start, end)}'
        '${end < code.length ? '…' : ''}';
    if (col >= 0) col = col - start + (start > 0 ? 1 : 0);
  }
  b.writeln('${a.dim(gutter)}$code');
  if (col >= 0 && col <= code.length) {
    b.writeln('${a.dim(blank)}${' ' * col}${a.severity(f.severity, '^')}');
  }
}

String renderTerminal(List<ScriptReport> reports, RenderOptions o) {
  final t = Messages(o.lang);
  final a = _Ansi(o.color);
  final b = StringBuffer();
  for (final r in reports) {
    final title = '${t.reportTitle}${t.colon}${r.script.path}';
    b.writeln(a.bold('═══ $title ═══'));
    b.writeln('${t.dialect}${t.colon}${r.script.dialectLabel}    '
        '${t.lines}${t.colon}${t.linesDetail(r.script.totalLines, r.script.codeLines, r.script.commentLines)}');
    b.writeln(a.dim('${t.tools}${t.colon}${_toolsLine(r, t)}'));
    final pl = _profileLine(r, t);
    if (pl != null) b.writeln(a.dim(pl));
    b.writeln();

    final sevHeads = [
      for (final s in Severity.values) _pad(s.label, 9, left: true)
    ];
    b.writeln(a.bold('${_pad(t.category_, 17)}${_pad(t.score, 20)}'
        '${sevHeads.join()}${_pad(t.total, 8, left: true)}'));
    for (final s in r.scores) {
      final sc = fmtScore(s.score, o.lang);
      b.write(_pad(t.category(s.category), 17));
      b.write(_pad(
          '${a.score(s.score, _pad(sc, 5, left: true))} ${a.score(s.score, _bar(s.score))}',
          20));
      for (final sev in Severity.values) {
        final n = s.count(sev);
        b.write(
            _pad(n == 0 ? a.dim('0') : a.severity(sev, '$n'), 9, left: true));
      }
      b.writeln(_pad('${s.total}', 8, left: true));
    }
    b.writeln();
    b.writeln(a.bold('${t.globalScore}${t.colon}') +
        a.score(r.global, '${fmtScore(r.global, o.lang)}/10 (${r.grade})'));
    if (r.suppressed > 0) b.writeln(a.dim(t.suppressedCount(r.suppressed)));
    final plan = planLine(r, t, o.lang);
    if (plan != null) b.writeln(a.bold('→ $plan'));
    if (o.explain && r.explanation.impacts.isNotEmpty) {
      b.writeln();
      b.writeln(a.bold(t.explainTitle));
      for (final i in r.explanation.impacts.take(10)) {
        b.writeln('  ${_pad('−${fmtScore(i.penalty, o.lang)}', 7)}'
            '${_pad('+${fmtScore(i.gain, o.lang)}', 7)}'
            '${a.severity(i.severity, _pad(i.severity.label, 9))}'
            '${_pad('${i.ruleId} [${i.tool}]', 26)}'
            '×${_pad('${i.occurrences}', 4)}'
            '${i.fixable ? a.dim(t.autoFix) : ''}');
      }
    }
    final cmp = r.comparison;
    if (cmp != null) {
      b.writeln();
      b.writeln(a.bold(t.baseline));
      b.writeln(
          '  ${t.comparisonLine(cmp.added.length, cmp.fixed, cmp.unchanged)}');
      b.writeln(
          '  ${t.globalScore}${t.colon}${fmtScore(cmp.previousGlobal, o.lang)} → '
          '${fmtScore(r.global, o.lang)} (${fmtDelta(r.global, cmp.previousGlobal, o.lang)})');
    }

    if (o.maxDetails != 0) {
      b.writeln();
      b.writeln(a.bold(cmp == null ? t.details : t.newIssuesOnly));
      if (detailFindings(r).isEmpty) b.writeln('  ${t.noIssue}');
      // Tri par gain rapide : une seule liste, la plus rentable d'abord.
      final sections = o.byQuickWin
          ? [(t.byQuickWin, sortByQuickWin(detailFindings(r), r.explanation))]
          : [
              for (final c in Category.values)
                (t.category(c), detailFindings(r, c))
            ];
      for (final (title, fs) in sections) {
        if (fs.isEmpty) continue;
        b.writeln(a.magenta('▶ $title (${fs.length})'));
        final shown = o.maxDetails == null ? fs : fs.take(o.maxDetails!);
        for (final f in shown) {
          b.writeln('  ${_pad(f.line == 0 ? t.wholeFile : 'L${f.line}', 9)}'
              '${a.severity(f.severity, _pad(f.severity.label, 9))}'
              '${a.dim(_pad('${f.ruleId} [${f.tool}]', 26))}${f.message}');
          if (o.showSource && f.line > 0) _writeSource(b, f, a, t);
          final help = f.hint ?? f.url;
          if (o.maxDetails == null && help != null) {
            b.writeln(a.dim('${' ' * 46}→ $help'));
          }
        }
        if (fs.length > shown.length) {
          b.writeln(a.dim('  ${t.moreIssues(fs.length - shown.length)}'));
        }
      }
    }
    b.writeln();
  }
  if (reports.length > 1) {
    b.writeln(a.bold(t.summaryTitle));
    final heads = [
      for (final c in Category.values)
        _pad(t.category(c).substring(0, 4), 7, left: true)
    ];
    b.writeln(a.bold(
        '${_pad(t.script, 40)}${heads.join()}${_pad(t.globalScore, 16, left: true)}'));
    for (final r in reports) {
      b.write(_pad(r.script.path, 40));
      for (final s in r.scores) {
        b.write(
            _pad(a.score(s.score, fmtScore(s.score, o.lang)), 7, left: true));
      }
      b.writeln(_pad(
          a.score(r.global, '${fmtScore(r.global, o.lang)} (${r.grade})'), 16,
          left: true));
    }
    b.writeln();
  }
  final missing = _missing(reports);
  if (missing.isNotEmpty) b.writeln(a.yellow(t.missingToolsHint(missing)));
  return b.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Markdown
// ─────────────────────────────────────────────────────────────────────────────

String _mdCell(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');

String renderMarkdown(List<ScriptReport> reports, RenderOptions o) {
  final t = Messages(o.lang);
  final b = StringBuffer();
  if (reports.length > 1) {
    b.writeln('# ${t.summaryTitle}\n');
    b.writeln(
        '| ${t.script} | ${Category.values.map(t.category).join(' | ')} | ${t.globalScore} |');
    b.writeln('|---|${'---:|' * Category.values.length}---:|');
    for (final r in reports) {
      b.writeln('| `${_mdCell(r.script.path)}` | '
          '${r.scores.map((s) => fmtScore(s.score, o.lang)).join(' | ')} | '
          '**${fmtScore(r.global, o.lang)}** (${r.grade}) |');
    }
    b.writeln();
  }
  final h = reports.length > 1 ? '##' : '#';
  for (final r in reports) {
    b.writeln('$h ${t.reportTitle}${t.colon}`${r.script.path}`\n');
    b.writeln('- **${t.dialect}**${t.colon}${r.script.dialectLabel}');
    b.writeln(
        '- **${t.lines}**${t.colon}${t.linesDetail(r.script.totalLines, r.script.codeLines, r.script.commentLines)}');
    b.writeln('- **${t.date}**${t.colon}${_date(r.date)}');
    b.writeln('- **${t.tools}**${t.colon}${_toolsLine(r, t)}');
    final pl = _profileLine(r, t);
    if (pl != null) b.writeln('- $pl');
    if (r.suppressed > 0) b.writeln('- ${t.suppressedCount(r.suppressed)}');
    b.writeln(
        '- **${t.globalScore}**${t.colon}**${fmtScore(r.global, o.lang)}/10** (${t.grade} ${r.grade})\n');

    b.writeln(
        '| ${t.category_} | ${t.score} | Critical | High | Medium | Low | ${t.total} |');
    b.writeln('|---|---:|---:|---:|---:|---:|---:|');
    for (final s in r.scores) {
      b.writeln(
          '| ${t.category(s.category)} | **${fmtScore(s.score, o.lang)}** | '
          '${Severity.values.map(s.count).join(' | ')} | ${s.total} |');
    }
    b.writeln('\n_${t.scoringNote}_\n');
    final plan = planLine(r, t, o.lang);
    if (plan != null) b.writeln('**→ $plan**\n');
    if (r.explanation.impacts.isNotEmpty) {
      b.writeln('$h# ${t.explainTitle}\n');
      b.writeln(
          '| ${t.rule} | ${t.category_} | ${t.severity} | ${t.occurrences} | ${t.pointsHeader} | ${t.gainHeader} | |');
      b.writeln('|---|---|---|---:|---:|---:|---|');
      for (final i in r.explanation.impacts.take(10)) {
        b.writeln('| `${i.ruleId}` (${i.tool}) | ${t.category(i.category)} | '
            '${i.severity.label} | ${i.occurrences} | −${fmtScore(i.penalty, o.lang)} | +${fmtScore(i.gain, o.lang)} | '
            '${i.fixable ? t.autoFix : ''} |');
      }
      b.writeln();
    }

    final cmp = r.comparison;
    if (cmp != null) {
      b.writeln('$h# ${t.baseline}\n');
      b.writeln(
          '${t.comparisonLine(cmp.added.length, cmp.fixed, cmp.unchanged)}\n');
      b.writeln(
          '| ${t.category_} | ${t.previous} | ${t.score} | ${t.evolution} |');
      b.writeln('|---|---:|---:|---:|');
      for (final s in r.scores) {
        final before = cmp.previousScores[s.category] ?? s.score;
        b.writeln('| ${t.category(s.category)} | ${fmtScore(before, o.lang)} | '
            '${fmtScore(s.score, o.lang)} | ${fmtDelta(s.score, before, o.lang)} |');
      }
      b.writeln(
          '| **${t.globalScore}** | ${fmtScore(cmp.previousGlobal, o.lang)} | '
          '**${fmtScore(r.global, o.lang)}** | ${fmtDelta(r.global, cmp.previousGlobal, o.lang)} |\n');
    }

    b.writeln('$h# ${cmp == null ? t.details : t.newIssuesOnly}\n');
    if (detailFindings(r).isEmpty) b.writeln('${t.noIssue}\n');
    for (final c in Category.values) {
      final fs = detailFindings(r, c);
      if (fs.isEmpty) continue;
      b.writeln('$h## ${t.category(c)} (${fs.length})\n');
      b.writeln(
          '| ${t.line} | ${t.severity} | ${t.tool} | ${t.rule} | ${t.message} |');
      b.writeln('|---:|---|---|---|---|');
      for (final f in fs) {
        final snippet = f.line == 0
            ? ''
            : f.snippet == null
                ? '<br>_${t.maskedSecret}_'
                : '<br>`${_mdCell(f.snippet!.trimLeft().replaceAll('`', "'"))}`';
        final rule =
            f.url == null ? '`${f.ruleId}`' : '[`${f.ruleId}`](${f.url})';
        final hint = f.hint == null ? '' : '<br>→ _${_mdCell(f.hint!)}_';
        b.writeln('| ${_loc(f, t)} | ${f.severity.label} | ${f.tool} | $rule | '
            '${_mdCell(f.message)}$snippet$hint |');
      }
      b.writeln();
    }
  }
  final missing = _missing(reports);
  if (missing.isNotEmpty) b.writeln('> ${t.missingToolsHint(missing)}\n');
  b.writeln('---\n_check-script ${appVersion}_');
  return b.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// AsciiDoc
// ─────────────────────────────────────────────────────────────────────────────

String _adocCell(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');

String renderAsciidoc(List<ScriptReport> reports, RenderOptions o) {
  final t = Messages(o.lang);
  final b = StringBuffer();
  final multi = reports.length > 1;
  b.writeln(
      '= ${multi ? t.summaryTitle : '${t.reportTitle}${t.colon}${reports.first.script.path}'}');
  b.writeln(':toc:');
  b.writeln(':lang: ${o.lang.name}');
  b.writeln();
  if (multi) {
    b.writeln(
        '[cols="3,${List.filled(Category.values.length, '1').join(',')},1",options="header"]');
    b.writeln('|===');
    b.writeln(
        '|${t.script} ${Category.values.map((c) => '|${t.category(c)}').join(' ')} |${t.globalScore}');
    for (final r in reports) {
      b.writeln('|`${_adocCell(r.script.path)}` '
          '${r.scores.map((s) => '|${fmtScore(s.score, o.lang)}').join(' ')} '
          '|*${fmtScore(r.global, o.lang)}* (${r.grade})');
    }
    b.writeln('|===\n');
  }
  // Niveaux de titre : section du script (multi), détails, catégories.
  final h = multi ? '===' : '==';
  for (final r in reports) {
    if (multi) b.writeln('== ${t.reportTitle}${t.colon}`${r.script.path}`\n');
    b.writeln('[horizontal]');
    b.writeln('${t.dialect}:: ${r.script.dialectLabel}');
    b.writeln(
        '${t.lines}:: ${t.linesDetail(r.script.totalLines, r.script.codeLines, r.script.commentLines)}');
    b.writeln('${t.date}:: ${_date(r.date)}');
    b.writeln('${t.tools}:: ${_toolsLine(r, t)}');
    final pl = _profileLine(r, t);
    if (pl != null) {
      b.writeln('${t.profile}:: ${pl.split(t.colon).skip(1).join(t.colon)}');
    }
    b.writeln(
        '${t.globalScore}:: *${fmtScore(r.global, o.lang)}/10* (${t.grade} ${r.grade})');
    b.writeln();
    b.writeln('[cols="3,1,1,1,1,1,1",options="header"]');
    b.writeln('|===');
    b.writeln(
        '|${t.category_} |${t.score} |Critical |High |Medium |Low |${t.total}');
    for (final s in r.scores) {
      b.writeln('|${t.category(s.category)} |*${fmtScore(s.score, o.lang)}* '
          '${Severity.values.map((v) => '|${s.count(v)}').join(' ')} |${s.total}');
    }
    b.writeln('|===\n');
    b.writeln('NOTE: ${t.scoringNote}\n');
    if (r.suppressed > 0) b.writeln('${t.suppressedCount(r.suppressed)}.\n');

    final cmp = r.comparison;
    if (cmp != null) {
      b.writeln('$h ${t.baseline}\n');
      b.writeln(
          '${t.comparisonLine(cmp.added.length, cmp.fixed, cmp.unchanged)}\n');
      b.writeln('[cols="3,1,1,1",options="header"]');
      b.writeln('|===');
      b.writeln('|${t.category_} |${t.previous} |${t.score} |${t.evolution}');
      for (final s in r.scores) {
        final before = cmp.previousScores[s.category] ?? s.score;
        b.writeln('|${t.category(s.category)} |${fmtScore(before, o.lang)} '
            '|${fmtScore(s.score, o.lang)} |${fmtDelta(s.score, before, o.lang)}');
      }
      b.writeln('|*${t.globalScore}* |${fmtScore(cmp.previousGlobal, o.lang)} '
          '|*${fmtScore(r.global, o.lang)}* |${fmtDelta(r.global, cmp.previousGlobal, o.lang)}');
      b.writeln('|===\n');
    }

    b.writeln('$h ${cmp == null ? t.details : t.newIssuesOnly}\n');
    if (detailFindings(r).isEmpty) b.writeln('${t.noIssue}\n');
    for (final c in Category.values) {
      final fs = detailFindings(r, c);
      if (fs.isEmpty) continue;
      b.writeln('$h= ${t.category(c)} (${fs.length})\n');
      b.writeln('[cols="1,1,1,1,6",options="header"]');
      b.writeln('|===');
      b.writeln(
          '|${t.line} |${t.severity} |${t.tool} |${t.rule} |${t.message}');
      for (final f in fs) {
        final snippet = f.line == 0
            ? ''
            : f.snippet == null
                ? ' +\n_${_adocCell(t.maskedSecret)}_'
                : ' +\n`+${_adocCell(f.snippet!.trimLeft())}+`';
        final rule =
            f.url == null ? '`${f.ruleId}`' : '${f.url}[`${f.ruleId}`]';
        final hint = f.hint == null ? '' : ' +\n_→ ${_adocCell(f.hint!)}_';
        b.writeln('|${_loc(f, t)} |${f.severity.label} |${f.tool} |$rule '
            '|${_adocCell(f.message)}$snippet$hint');
      }
      b.writeln('|===\n');
    }
  }
  final missing = _missing(reports);
  if (missing.isNotEmpty) {
    b.writeln('WARNING: ${t.missingToolsHint(missing)}\n');
  }
  b.writeln('_check-script ${appVersion}_');
  return b.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON (consommé par l'interface Flutter et par l'intégration continue)
// ─────────────────────────────────────────────────────────────────────────────

String renderJson(List<ScriptReport> reports) =>
    const JsonEncoder.withIndent('  ').convert({
      'tool': 'check-script',
      'version': appVersion,
      'reports': [for (final r in reports) r.toJson()],
    });
