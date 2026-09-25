/// Formats d'intégration continue : JUnit XML (onglet Tests de Jenkins et
/// de GitLab) et annotations GitHub Actions (commandes de workflow).
library;

import '../model/finding.dart';
import '../model/report.dart';
import '../reporters/reporters.dart' show fmtScore;
import '../i18n.dart';

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Caractères de contrôle interdits en XML 1.0.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _path(String p) => p.startsWith('./') ? p.substring(2) : p;

/// JUnit XML : une suite par script, un cas en échec par problème (type :
/// sévérité) ; un script sans problème compte un cas réussi.
String renderJunit(List<ScriptReport> reports) {
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
  final total = reports.fold<int>(
      0, (n, r) => n + (r.findings.isEmpty ? 1 : r.findings.length));
  final failures = reports.fold<int>(0, (n, r) => n + r.findings.length);
  b.writeln('<testsuites name="check-script" tests="$total" '
      'failures="$failures">');
  for (final r in reports) {
    final path = _xml(_path(r.script.path));
    final n = r.findings.isEmpty ? 1 : r.findings.length;
    b.writeln('  <testsuite name="$path" tests="$n" '
        'failures="${r.findings.length}" '
        'timestamp="${r.date.toIso8601String().split('.').first}">');
    b.writeln('    <properties><property name="score" '
        'value="${fmtScore(r.global, Lang.en)}"/><property name="grade" '
        'value="${r.grade}"/></properties>');
    if (r.findings.isEmpty) {
      b.writeln('    <testcase classname="$path" name="check-script"/>');
    }
    for (final f in r.findings) {
      final where = f.line > 0 ? ':${f.line}' : '';
      b.writeln('    <testcase classname="$path" '
          'name="${_xml('${f.ruleId}$where')}" file="$path"'
          '${f.line > 0 ? ' line="${f.line}"' : ''}>');
      b.writeln('      <failure type="${f.severity.label}" '
          'message="${_xml(f.message)}">'
          '${_xml([
        '${f.tool} ${f.ruleId} — ${f.category.name} / ${f.severity.label}',
        '$path$where',
        if (f.snippet != null) f.snippet!,
        if (f.hint != null) f.hint!,
        if (f.url != null) f.url!,
      ].join('\n'))}</failure>');
      b.writeln('    </testcase>');
    }
    b.writeln('  </testsuite>');
  }
  b.writeln('</testsuites>');
  return b.toString();
}

String _ghData(String s) =>
    s.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
String _ghProp(String s) =>
    _ghData(s).replaceAll(':', '%3A').replaceAll(',', '%2C');

/// Annotations GitHub Actions : une commande `::error` / `::warning` /
/// `::notice` par problème, affichée sur la ligne dans les pull requests.
String renderGithub(List<ScriptReport> reports) {
  final b = StringBuffer();
  for (final r in reports) {
    for (final f in r.findings) {
      final level = switch (f.severity) {
        Severity.critical || Severity.high => 'error',
        Severity.medium => 'warning',
        Severity.low => 'notice',
      };
      final props = [
        'file=${_ghProp(_path(r.script.path))}',
        if (f.line > 0) 'line=${f.line}',
        if (f.line > 0 && f.column > 0) 'col=${f.column}',
        'title=${_ghProp('${f.ruleId} (${f.tool}, ${f.severity.label})')}',
      ].join(',');
      final text = f.hint == null ? f.message : '${f.message}\n${f.hint}';
      b.writeln('::$level $props::${_ghData(text)}');
    }
  }
  return b.toString();
}
