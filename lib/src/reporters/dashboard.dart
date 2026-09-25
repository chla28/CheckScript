/// Tableau de bord d'équipe : plusieurs dépôts (dossiers) sur une page HTML
/// autonome — note moyenne, niveaux, problèmes graves, évolution
/// (historique), règles les plus fréquentes et scripts les plus faibles.
library;

import 'dart:convert';

import '../history.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../model/report.dart';
import '../version.dart';
import 'reporters.dart';

const _htmlEscape = HtmlEscape();
String _e(String s) => _htmlEscape.convert(s);

/// Un dépôt du tableau de bord : ses rapports et son historique.
class DashboardRepo {
  final String name;
  final String path;
  final List<ScriptReport> reports;

  /// Analyses précédentes (la plus récente en dernier), analyse courante
  /// comprise.
  final List<HistoryEntry> history;

  const DashboardRepo(this.name, this.path, this.reports, this.history);

  double get average => reports.isEmpty
      ? 0
      : reports.map((r) => r.global).reduce((a, b) => a + b) / reports.length;

  int count(Severity s) => reports.fold(
      0, (n, r) => n + r.findings.where((f) => f.severity == s).length);
}

const _css = r'''
:root{--bg:#fbfbfa;--fg:#1d1d1f;--muted:#6b6b70;--card:#fff;--line:#e4e4e7;
--crit:#b3261e;--high:#d9480f;--med:#b8860b;--low:#2f6fb5;--ok:#2e7d32}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#ececf1;--muted:#a1a1aa;
--card:#1f1f23;--line:#33333a;--crit:#ff6b6b;--high:#ff922b;--med:#ffd43b;--low:#74c0fc;--ok:#69db7c}}
*{box-sizing:border-box}body{margin:0;font:15px/1.5 system-ui,sans-serif;background:var(--bg);color:var(--fg)}
main{max-width:1100px;margin:0 auto;padding:24px 16px}h1{font-size:1.5rem;margin:.2em 0}
h2{font-size:1.2rem;margin:1.6em 0 .6em}.muted{color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:12px 0}
.wide{overflow-x:auto}table{border-collapse:collapse;width:100%}
th,td{padding:6px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:middle;white-space:nowrap}
td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}table.sortable th{cursor:pointer;user-select:none}
.kpi{display:flex;flex-wrap:wrap;gap:24px}.kpi div{min-width:120px}.kpi strong{display:block;font-size:1.4rem}
.critical{color:var(--crit)}.high{color:var(--high)}.medium{color:var(--med)}.low{color:var(--low)}
svg.spark{vertical-align:middle}
''';

const _js = r'''
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

/// Petite courbe SVG des notes moyennes (0 à 10).
String sparkline(List<double> values, {int width = 120, int height = 28}) {
  if (values.length < 2) return '';
  final pts = <String>[];
  for (var i = 0; i < values.length; i++) {
    final x = 2 + (width - 4) * i / (values.length - 1);
    final y = 2 + (height - 4) * (1 - values[i].clamp(0, 10) / 10);
    pts.add('${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
  }
  return '<svg class="spark" width="$width" height="$height" '
      'viewBox="0 0 $width $height" aria-hidden="true">'
      '<polyline fill="none" stroke="${_color(values.last)}" stroke-width="2" '
      'points="${pts.join(' ')}"/></svg>';
}

String renderDashboard(List<DashboardRepo> repos, Lang lang) {
  final t = Messages(lang);
  final b = StringBuffer();
  final all = [for (final r in repos) ...r.reports];
  final avg = all.isEmpty
      ? 0.0
      : all.map((r) => r.global).reduce((a, x) => a + x) / all.length;
  final title = t.dashboardTitle(repos.length);
  b.writeln(
      '<!DOCTYPE html><html lang="${lang.name}"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>${_e(title)}</title><style>$_css</style></head><body><main>');
  b.writeln('<h1>${_e(title)}</h1>'
      '<p class="muted">${DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}</p>');

  // Indicateurs globaux.
  b.writeln('<div class="card kpi">'
      '<div><span class="muted">${_e(t.scriptsAffected)}</span><strong>${all.length}</strong></div>'
      '<div><span class="muted">${_e(t.averageScore)}</span>'
      '<strong style="color:${_color(avg)}">${fmtScore(avg, lang)}/10</strong></div>'
      '<div><span class="muted">${_e(t.issuesBySeverity)}</span><strong>'
      '${[
    for (final s in Severity.values)
      '<span class="${s.name}">${s.label} ${repos.fold(0, (n, r) => n + r.count(s))}</span>'
  ].join(' · ')}</strong></div></div>');

  // Un dépôt par ligne (triable).
  b.writeln('<div class="card wide"><p class="muted">${_e(t.sortHint)}</p>'
      '<table class="sortable"><thead><tr><th>${_e(t.repository)}</th>'
      '<th class="n">${_e(t.scriptsAffected)}</th><th class="n">${_e(t.averageScore)}</th>'
      '<th class="n">${_e(t.evolution)}</th><th>${_e(t.trendHeader)}</th>'
      '<th class="n">Critical</th><th class="n">High</th>'
      '<th>${_e(t.gradeDistribution)}</th></tr></thead><tbody>');
  for (var i = 0; i < repos.length; i++) {
    final r = repos[i];
    final h = r.history;
    final prev = h.length >= 2 ? h[h.length - 2].average : null;
    final grades = <String, int>{};
    for (final x in r.reports) {
      grades[x.grade] = (grades[x.grade] ?? 0) + 1;
    }
    b.writeln('<tr><td><a href="#r$i">${_e(r.name)}</a></td>'
        '<td class="n" data-v="${r.reports.length}">${r.reports.length}</td>'
        '<td class="n" data-v="${r.average}"><strong style="color:${_color(r.average)}">'
        '${fmtScore(r.average, lang)}</strong></td>'
        '<td class="n" data-v="${prev == null ? 0 : r.average - prev}">'
        '${prev == null ? '—' : fmtDelta(r.average, prev, lang)}</td>'
        '<td>${sparkline([for (final e in h) e.average])}</td>'
        '<td class="n critical" data-v="${r.count(Severity.critical)}">${r.count(Severity.critical)}</td>'
        '<td class="n high" data-v="${r.count(Severity.high)}">${r.count(Severity.high)}</td>'
        '<td>${[
      for (final g in ['A', 'B', 'C', 'D', 'E'])
        if (grades[g] != null) '$g ${grades[g]}'
    ].join(' · ')}</td></tr>');
  }
  b.writeln('</tbody></table></div>');

  // Règles les plus fréquentes, tous dépôts confondus.
  final occ = <String, (Finding, int, Set<int>)>{};
  for (var i = 0; i < repos.length; i++) {
    for (final r in repos[i].reports) {
      for (final f in r.findings) {
        final k = '${f.tool}/${f.ruleId}';
        final cur = occ[k];
        occ[k] = (cur?.$1 ?? f, (cur?.$2 ?? 0) + 1, {...?cur?.$3, i});
      }
    }
  }
  final top = occ.values.toList()..sort((a, x) => x.$2.compareTo(a.$2));
  if (top.isNotEmpty) {
    b.writeln('<h2>${_e(t.topRules)}</h2><div class="card wide"><table>'
        '<tr><th>${t.rule}</th><th>${t.category_}</th>'
        '<th class="n">${t.occurrences}</th><th class="n">${_e(t.repositories)}</th>'
        '<th>${t.message}</th></tr>');
    for (final (f, n, rs) in top.take(15)) {
      b.writeln(
          '<tr><td><code>${_e(f.ruleId)}</code> <span class="muted">${_e(f.tool)}</span></td>'
          '<td>${_e(t.category(f.category))}</td><td class="n">$n</td>'
          '<td class="n">${rs.length}</td><td style="white-space:normal">${_e(f.message)}</td></tr>');
    }
    b.writeln('</table></div>');
  }

  // Scripts les plus faibles de chaque dépôt.
  for (var i = 0; i < repos.length; i++) {
    final r = repos[i];
    final worst = [...r.reports]..sort((a, x) => a.global.compareTo(x.global));
    b.writeln(
        '<h2 id="r$i">${_e(r.name)} <span class="muted" style="font-size:.7em">'
        '${_e(r.path)}</span></h2><div class="card wide"><table>'
        '<tr><th>${_e(t.weakestScripts)}</th><th class="n">${t.globalScore}</th>'
        '<th class="n">${t.grade}</th></tr>');
    for (final s in worst.take(5)) {
      b.writeln('<tr><td><code>${_e(s.script.path)}</code></td>'
          '<td class="n" style="color:${_color(s.global)}">${fmtScore(s.global, lang)}</td>'
          '<td class="n">${s.grade}</td></tr>');
    }
    b.writeln('</table></div>');
  }

  b.writeln(
      '<p class="muted">check-script $appVersion</p></main><script>$_js</script></body></html>');
  return b.toString();
}
