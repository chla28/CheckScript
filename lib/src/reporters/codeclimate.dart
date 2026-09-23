/// Export « Code Quality » de GitLab (format CodeClimate JSON) : affiché dans
/// le widget des merge requests (`artifacts: reports: codequality`).
library;

import 'dart:convert';

import '../model/finding.dart';
import '../model/report.dart';

String _severity(Severity s) => switch (s) {
      Severity.critical => 'blocker',
      Severity.high => 'critical',
      Severity.medium => 'major',
      Severity.low => 'minor',
    };

String renderCodeClimate(List<ScriptReport> reports) =>
    const JsonEncoder.withIndent('  ').convert([
      for (final r in reports)
        for (final f in r.findings)
          {
            'type': 'issue',
            'check_name': '${f.tool}/${f.ruleId}',
            'description':
                f.hint == null ? f.message : '${f.message} — ${f.hint}',
            'categories': [
              switch (f.category) {
                Category.security => 'Security',
                Category.robustness => 'Bug Risk',
                Category.maintainability => 'Style',
                Category.portability => 'Compatibility',
                Category.performance => 'Performance',
              }
            ],
            'severity': _severity(f.severity),
            'fingerprint':
                f.fingerprint ?? '${r.script.path}:${f.line}:${f.ruleId}',
            'location': {
              'path': r.script.path.startsWith('./')
                  ? r.script.path.substring(2)
                  : r.script.path,
              'lines': {'begin': f.line < 1 ? 1 : f.line},
            },
          }
    ]);
