/// Rapport HTML autonome (un seul fichier, sans ressource externe) : synthèse,
/// filtres par catégorie et sévérité, source annotée ligne par ligne.
library;

import 'dart:convert';

import '../fixer.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../model/report.dart';
import '../rules/examples.dart';
import '../version.dart';
import 'reporters.dart';

const _htmlEscape = HtmlEscape();
String _e(String s) => _htmlEscape.convert(s);

const _css = r'''
:root{--bg:#fbfbfa;--fg:#1d1d1f;--muted:#6b6b70;--card:#fff;--line:#e4e4e7;
--crit:#b3261e;--high:#d9480f;--med:#b8860b;--low:#2f6fb5;--ok:#2e7d32;--code:#f4f4f5}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#ececf1;--muted:#a1a1aa;
--card:#1f1f23;--line:#33333a;--crit:#ff6b6b;--high:#ff922b;--med:#ffd43b;--low:#74c0fc;
--ok:#69db7c;--code:#26262b}}
*{box-sizing:border-box}body{margin:0;font:15px/1.5 system-ui,sans-serif;background:var(--bg);color:var(--fg)}
main{max-width:1100px;margin:0 auto;padding:24px 16px}h1{font-size:1.5rem;margin:.2em 0}
h2{font-size:1.2rem;margin:1.6em 0 .6em}.muted{color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:12px 0}
table{border-collapse:collapse;width:100%}table.sortable th{cursor:pointer;user-select:none}
td pre.snip,td pre.diff{max-width:min(640px,55vw)}
.wide{overflow-x:auto}.wide table{font-size:.9em}.wide td,.wide th{white-space:nowrap}
.kpi{display:flex;flex-wrap:wrap;gap:24px}.kpi div{min-width:120px}.kpi strong{display:block;font-size:1.4rem}th,td{padding:6px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}
.bar{display:inline-block;height:8px;border-radius:4px;background:var(--line);width:120px;vertical-align:middle;margin-left:8px}
.bar>i{display:block;height:100%;border-radius:4px}
.sev{font-weight:600;font-size:.85em}.critical{color:var(--crit)}.high{color:var(--high)}.medium{color:var(--med)}.low{color:var(--low)}
.global{font-size:2rem;font-weight:700}.filters label{margin-right:14px;white-space:nowrap}
.hint{color:var(--muted);font-size:.9em}code,pre{font-family:ui-monospace,monospace;font-size:.88em}
pre.src{background:var(--code);border-radius:8px;padding:8px 0;overflow-x:auto;margin:0}
.src .l{display:block;padding:0 12px;white-space:pre}.src .l[data-sev]{border-left:4px solid}
.src .l[data-sev=critical]{border-color:var(--crit)}.src .l[data-sev=high]{border-color:var(--high)}
.src .l[data-sev=medium]{border-color:var(--med)}.src .l[data-sev=low]{border-color:var(--low)}
.src .no{display:inline-block;width:3.5em;color:var(--muted);user-select:none}
.src .l:target{background:rgba(127,127,127,.18)}details summary{cursor:pointer}
pre.snip{background:var(--code);border-radius:6px;padding:4px 8px;margin:4px 0;overflow-x:auto;white-space:pre}
.lbl{font-size:.8em;font-weight:600;color:var(--muted);margin-top:6px}
pre.diff{background:var(--code);border-radius:6px;padding:4px 0;margin:4px 0;overflow-x:auto}
.diff>span{display:block;padding:0 8px;white-space:pre}
.diff .del,pre.bad{background:rgba(220,38,38,.12)}.diff .add,pre.good{background:rgba(22,163,74,.14)}
details.ex{margin-top:4px}details.ex summary{font-size:.9em;color:var(--muted)}
''';

const _js = r'''
function applyFilters(){
  const on=new Set([...document.querySelectorAll('.filters input:checked')].map(i=>i.value));
  document.querySelectorAll('tr.finding').forEach(tr=>{
    tr.hidden=!(on.has(tr.dataset.cat)&&on.has(tr.dataset.sev));
  });
}
document.querySelectorAll('.filters input').forEach(i=>i.addEventListener('change',applyFilters));
document.querySelectorAll('table.sortable th').forEach((th,col)=>th.addEventListener('click',()=>{
  const tb=th.closest('table').tBodies[0];
  const asc=th.dataset.dir!=='asc'; th.dataset.dir=asc?'asc':'desc';
  const v=tr=>{const c=tr.cells[col];return c.dataset.v!==undefined?parseFloat(c.dataset.v):c.textContent.trim();};
  [...tb.rows].sort((a,b)=>{const x=v(a),y=v(b);const r=typeof x==='number'?x-y:String(x).localeCompare(y);return asc?r:-r;})
    .forEach(r=>tb.appendChild(r));
}));
''';

String _color(double v) =>
    v >= 7.5 ? 'var(--ok)' : (v >= 5 ? 'var(--med)' : 'var(--crit)');

String renderHtml(List<ScriptReport> reports, RenderOptions o) {
  final t = Messages(o.lang);
  final b = StringBuffer();
  final title = reports.length == 1
      ? '${t.reportTitle}${t.colon}${reports.first.script.path}'
      : t.summaryTitle;
  b.writeln(
      '<!DOCTYPE html><html lang="${o.lang.name}"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>${_e(title)}</title><style>$_css</style></head><body><main>');
  b.writeln('<h1>${_e(title)}</h1>');

  // Filtres communs.
  b.writeln('<div class="card filters"><strong>${t.filter}</strong> ');
  for (final c in Category.values) {
    b.writeln(
        '<label><input type="checkbox" value="${c.name}" checked> ${_e(t.category(c))}</label>');
  }
  b.writeln('<br>');
  for (final s in Severity.values) {
    b.writeln(
        '<label class="sev ${s.name}"><input type="checkbox" value="${s.name}" checked> ${s.label}</label>');
  }
  b.writeln('</div>');

  if (reports.length > 1) _folderSummary(b, reports, t, o.lang);

  for (var i = 0; i < reports.length; i++) {
    final r = reports[i];
    final sid = 's$i';
    b.writeln('<section id="$sid">');
    if (reports.length > 1) {
      b.writeln('<h2><code>${_e(r.script.path)}</code> '
          '<a class="muted" style="font-size:.7em" href="#summary">'
          '${_e(t.backToSummary)}</a></h2>');
    }
    b.writeln(
        '<div class="card"><div class="global" style="color:${_color(r.global)}">'
        '${fmtScore(r.global, o.lang)}/10 <span class="muted">(${r.grade})</span></div>');
    b.writeln(
        '<div class="muted">${t.dialect}${t.colon}${_e(r.script.dialectLabel)} · '
        '${t.lines}${t.colon}${_e(t.linesDetail(r.script.totalLines, r.script.codeLines, r.script.commentLines))}'
        '${r.profile == 'standard' ? '' : ' · ${t.profile}${t.colon}${r.profile}'}'
        '${r.contexts.isEmpty ? '' : ' · ${t.contexts}${t.colon}${r.contexts.join(', ')}'}</div>');
    b.writeln('<div class="muted">${t.tools}${t.colon}${_e([
      for (final run in r.tools)
        '${run.tool}${run.version != null ? ' ${run.version}' : ''} (${t.toolStatus(run.status)})'
    ].join(', '))}</div>');
    if (r.suppressed > 0) {
      b.writeln(
          '<div class="muted">${_e(t.suppressedCount(r.suppressed))}</div>');
    }
    b.writeln('</div>');

    b.writeln(
        '<div class="card"><table><tr><th>${t.category_}</th><th>${t.score}</th>');
    for (final s in Severity.values) {
      b.writeln('<th class="n">${s.label}</th>');
    }
    b.writeln('<th class="n">${t.total}</th></tr>');
    for (final s in r.scores) {
      b.writeln('<tr><td>${_e(t.category(s.category))}</td><td>'
          '<strong style="color:${_color(s.score)}">${fmtScore(s.score, o.lang)}</strong>'
          '<span class="bar"><i style="width:${(s.score * 10).round()}%;background:${_color(s.score)}"></i></span></td>');
      for (final sev in Severity.values) {
        b.writeln('<td class="n">${s.count(sev)}</td>');
      }
      b.writeln('<td class="n">${s.total}</td></tr>');
    }
    b.writeln('</table><p class="muted">${_e(t.scoringNote)}</p></div>');
    _explainHtml(b, r, t, o.lang);

    final cmp = r.comparison;
    if (cmp != null) {
      b.writeln('<div class="card"><strong>${t.baseline}</strong><br>'
          '${_e(t.comparisonLine(cmp.added.length, cmp.fixed, cmp.unchanged))}<br>'
          '${t.globalScore}${t.colon}${fmtScore(cmp.previousGlobal, o.lang)} → '
          '${fmtScore(r.global, o.lang)} (${fmtDelta(r.global, cmp.previousGlobal, o.lang)})</div>');
    }

    final fs = detailFindings(r);
    b.writeln(
        '<h2>${cmp == null ? t.details : t.newIssuesOnly} (${fs.length})</h2>');
    if (fs.isEmpty) {
      b.writeln('<p>${t.noIssue}</p>');
    } else {
      b.writeln(
          '<div class="card"><table><tr><th class="n">${t.line}</th><th>${t.severity}</th>'
          '<th>${t.category_}</th><th>${t.rule}</th><th>${t.message}</th></tr>');
      for (final f in fs) {
        final line = f.line == 0
            ? t.wholeFile
            : '<a href="#$sid-L${f.line}">${f.line}</a>';
        final snip = f.line == 0
            ? ''
            : f.snippet == null
                ? '<div class="hint">${_e(t.maskedSecret)}</div>'
                : '<pre class="snip">${_e(f.snippet!.trimLeft())}</pre>';
        final rule = f.url == null
            ? '<code>${_e(f.ruleId)}</code>'
            : '<a href="${_e(f.url!)}"><code>${_e(f.ruleId)}</code></a>';
        b.writeln(
            '<tr class="finding" data-cat="${f.category.name}" data-sev="${f.severity.name}">'
            '<td class="n">$line</td><td class="sev ${f.severity.name}">${f.severity.label}</td>'
            '<td>${_e(t.category(f.category))}</td><td>$rule<br><span class="muted">${_e(f.tool)}</span></td>'
            '<td>${_e(f.message)}$snip${f.hint == null ? '' : '<div class="hint">→ ${_e(f.hint!)}</div>'}'
            '${_fixHtml(f, r.script.displayLines, t, o.lang)}</td></tr>');
      }
      b.writeln('</table></div>');
    }

    // Source annotée : chaque ligne porte la sévérité la plus forte ; les
    // lignes masquées par le moteur (secret potentiel) ne sont pas recopiées.
    final worst = <int, Severity>{};
    final notes = <int, List<Finding>>{};
    final masked = <int>{};
    for (final f in r.findings) {
      if (f.line < 1) continue;
      if (f.snippet == null) masked.add(f.line);
      final w = worst[f.line];
      if (w == null || f.severity.index < w.index) worst[f.line] = f.severity;
      (notes[f.line] ??= []).add(f);
    }
    b.writeln(
        '<details class="card"><summary>${t.source}</summary><pre class="src">');
    for (var n = 1; n <= r.script.displayLines.length; n++) {
      final sev = worst[n];
      final tip = notes[n]?.map((f) => '${f.ruleId}: ${f.message}').join('\n');
      b.write('<span class="l" id="$sid-L$n"'
          '${sev == null ? '' : ' data-sev="${sev.name}" title="${_e(tip!)}"'}>'
          '<span class="no">$n</span>${masked.contains(n) ? '<span class="muted">${_e(t.maskedSecret)}</span>' : _e(r.script.displayLines[n - 1])}</span>');
    }
    b.writeln('</pre></details></section>');
  }

  b.writeln(
      '<p class="muted">check-script $appVersion</p></main><script>$_js</script></body></html>');
  return b.toString();
}

/// Correction concrète (lignes avant / après) ou, à défaut, exemple générique
/// de la règle ; chaîne vide si aucun des deux n'existe.
String _fixHtml(Finding f, List<String> lines, Messages t, Lang lang) {
  final p = fixPreview(f, lines);
  if (p != null) {
    final (_, before, after) = p;
    String part(String text, String cls, String sign) => [
          for (final l in text.split('\n'))
            '<span class="$cls">$sign ${_e(l)}</span>'
        ].join();
    return '<div class="lbl">${_e(t.suggestedFix)}</div><pre class="diff">'
        '${part(before, 'del', '-')}${part(after, 'add', '+')}</pre>';
  }
  final ex = exampleFor(f.ruleId);
  if (ex == null) return '';
  return '<details class="ex"><summary>${_e(t.fixExample)}</summary>'
      '<div class="lbl">${_e(t.avoid)}</div><pre class="snip bad">${_e(ex.badOf(lang))}</pre>'
      '<div class="lbl">${_e(t.writeInstead)}</div><pre class="snip good">${_e(ex.goodOf(lang))}</pre></details>';
}

/// Synthèse d'un dossier : indicateurs, tableau triable des scripts, règles
/// les plus fréquentes.
void _folderSummary(
    StringBuffer b, List<ScriptReport> reports, Messages t, Lang lang) {
  final python = reports.where((r) => r.script.dialect.isPython).length;
  final avg =
      reports.map((r) => r.global).reduce((a, x) => a + x) / reports.length;
  final grades = <String, int>{};
  for (final r in reports) {
    grades[r.grade] = (grades[r.grade] ?? 0) + 1;
  }
  final bySev = {for (final s in Severity.values) s: 0};
  for (final r in reports) {
    for (final f in r.findings) {
      bySev[f.severity] = bySev[f.severity]! + 1;
    }
  }

  b.writeln('<div class="card kpi" id="summary">'
      '<div><span class="muted">${_e(t.scriptsAffected)}</span><strong>${reports.length}</strong>'
      '<span class="muted">${_e(t.scriptsOverview(reports.length, reports.length - python, python))}</span></div>'
      '<div><span class="muted">${_e(t.averageScore)}</span>'
      '<strong style="color:${_color(avg)}">${fmtScore(avg, lang)}/10</strong></div>'
      '<div><span class="muted">${_e(t.gradeDistribution)}</span><strong>'
      '${[
    for (final g in ['A', 'B', 'C', 'D', 'E'])
      if (grades[g] != null) '$g ${grades[g]}'
  ].join(' · ')}'
      '</strong></div>'
      '<div><span class="muted">${_e(t.issuesBySeverity)}</span><strong>'
      '${[
    for (final s in Severity.values)
      '<span class="sev ${s.name}">${s.label} ${bySev[s]}</span>'
  ].join(' · ')}'
      '</strong></div></div>');

  // Tableau des scripts (triable) : note, niveau et problèmes graves
  // d'abord, notes par catégorie ensuite.
  b.writeln('<div class="card"><p class="muted">${_e(t.sortHint)}</p>'
      '<div class="wide"><table class="sortable"><thead><tr><th>${t.script}</th>'
      '<th class="n">${t.globalScore}</th><th class="n">${t.grade}</th>'
      '<th class="n">Critical</th><th class="n">High</th><th>${t.dialect}</th>');
  for (final c in Category.values) {
    b.writeln('<th class="n">${_e(t.category(c))}</th>');
  }
  b.writeln('</tr></thead><tbody>');
  for (var i = 0; i < reports.length; i++) {
    final r = reports[i];
    int count(Severity s) => r.findings.where((f) => f.severity == s).length;
    b.writeln(
        '<tr><td><a href="#s$i"><code>${_e(r.script.path)}</code></a></td>'
        '<td class="n" data-v="${r.global}"><strong style="color:${_color(r.global)}">'
        '${fmtScore(r.global, lang)}</strong></td><td class="n">${r.grade}</td>'
        '<td class="n" data-v="${count(Severity.critical)}">${count(Severity.critical)}</td>'
        '<td class="n" data-v="${count(Severity.high)}">${count(Severity.high)}</td>'
        '<td>${_e(r.script.dialectLabel)}</td>');
    for (final s in r.scores) {
      b.writeln(
          '<td class="n" data-v="${s.score}" style="color:${_color(s.score)}">'
          '${fmtScore(s.score, lang)}</td>');
    }
    b.writeln('</tr>');
  }
  b.writeln('</tbody></table></div></div>');

  // Règles les plus fréquentes.
  final occ = <String, List<Finding>>{};
  final scripts = <String, Set<int>>{};
  for (var i = 0; i < reports.length; i++) {
    for (final f in reports[i].findings) {
      final k = '${f.tool}\u0000${f.ruleId}';
      (occ[k] ??= []).add(f);
      (scripts[k] ??= {}).add(i);
    }
  }
  final top = occ.entries.toList()
    ..sort((a, x) {
      final c = x.value.length.compareTo(a.value.length);
      return c != 0 ? c : a.key.compareTo(x.key);
    });
  if (top.isEmpty) return;
  b.writeln('<h2>${_e(t.topRules)}</h2><div class="card">'
      '<table class="sortable"><thead><tr><th>${t.rule}</th><th>${t.category_}</th>'
      '<th>${t.severity}</th><th class="n">${t.occurrences}</th>'
      '<th class="n">${t.scriptsAffected}</th><th>${t.message}</th></tr></thead><tbody>');
  for (final e in top.take(20)) {
    final fs = e.value;
    final f = fs.first;
    final worst =
        fs.map((x) => x.severity).reduce((a, x) => x.index < a.index ? x : a);
    final rule = f.url == null
        ? '<code>${_e(f.ruleId)}</code>'
        : '<a href="${_e(f.url!)}"><code>${_e(f.ruleId)}</code></a>';
    b.writeln('<tr><td>$rule<br><span class="muted">${_e(f.tool)}</span></td>'
        '<td>${_e(t.category(f.category))}</td>'
        '<td class="sev ${worst.name}" data-v="${3 - worst.index}">${worst.label}</td>'
        '<td class="n" data-v="${fs.length}">${fs.length}</td>'
        '<td class="n" data-v="${scripts[e.key]!.length}">${scripts[e.key]!.length}</td>'
        '<td>${_e(f.message)}</td></tr>');
  }
  b.writeln('</tbody></table></div>');
}

/// Ce qui pèse sur la note et comment gagner un niveau.
void _explainHtml(StringBuffer b, ScriptReport r, Messages t, Lang lang) {
  final e = r.explanation;
  if (e.impacts.isEmpty) return;
  final plan = planLine(r, t, lang);
  b.writeln('<div class="card"><strong>${_e(t.explainTitle)}</strong>');
  if (plan != null) b.writeln('<p><strong>→ ${_e(plan)}</strong></p>');
  b.writeln('<table><tr><th>${t.rule}</th><th>${t.category_}</th>'
      '<th>${t.severity}</th><th class="n">${t.occurrences}</th>'
      '<th class="n">${t.pointsHeader}</th>'
      '<th class="n">${t.gainHeader}</th><th></th></tr>');
  for (final i in e.impacts.take(10)) {
    b.writeln('<tr><td><code>${_e(i.ruleId)}</code> '
        '<span class="muted">${_e(i.tool)}</span></td>'
        '<td>${_e(t.category(i.category))}</td>'
        '<td class="sev ${i.severity.name}">${i.severity.label}</td>'
        '<td class="n">${i.occurrences}</td>'
        '<td class="n">−${fmtScore(i.penalty, lang)}</td>'
        '<td class="n">+${fmtScore(i.gain, lang)}</td>'
        '<td class="muted">${i.fixable ? _e(t.autoFix) : ''}</td></tr>');
  }
  b.writeln('</table></div>');
}
