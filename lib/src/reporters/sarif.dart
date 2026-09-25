/// Export SARIF 2.1.0 : format standard des analyseurs statiques, lu par
/// GitLab, GitHub Code Scanning et les IDE.
library;

import 'dart:convert';

import '../model/finding.dart';
import '../model/report.dart';
import '../version.dart';

String _level(Severity s) => switch (s) {
      Severity.critical || Severity.high => 'error',
      Severity.medium => 'warning',
      Severity.low => 'note',
    };

/// Score « security-severity » (0–10) interprété par GitHub Code Scanning.
String _securitySeverity(Severity s) => switch (s) {
      Severity.critical => '9.5',
      Severity.high => '7.5',
      Severity.medium => '5.0',
      Severity.low => '2.0',
    };

String _uri(String path) => path.startsWith('./') ? path.substring(2) : path;

String renderSarif(List<ScriptReport> reports) {
  // Une règle SARIF par couple outil/règle, avec le classement observé.
  final rules = <String, Map<String, Object?>>{};
  final results = <Map<String, Object?>>[];
  String ruleKey(Finding f) => '${f.tool}/${f.ruleId}';

  for (final r in reports) {
    for (final f in r.findings) {
      final id = ruleKey(f);
      rules.putIfAbsent(
          id,
          () => {
                'id': id,
                'name': f.ruleId,
                'shortDescription': {'text': f.message},
                if (f.hint != null) 'help': {'text': f.hint},
                if (f.url != null) 'helpUri': f.url,
                'defaultConfiguration': {'level': _level(f.severity)},
                'properties': {
                  'category': f.category.name,
                  'tags': [f.category.name, f.tool],
                  if (f.category == Category.security)
                    'security-severity': _securitySeverity(f.severity),
                },
              });
      results.add({
        'ruleId': id,
        'level': _level(f.severity),
        'message': {
          'text': f.hint == null ? f.message : '${f.message} — ${f.hint}'
        },
        'locations': [
          {
            'physicalLocation': {
              'artifactLocation': {'uri': _uri(r.script.path)},
              'region': {
                'startLine': f.line < 1 ? 1 : f.line,
                if (f.column > 0) 'startColumn': f.column,
                if (f.line > 0 && f.snippet != null)
                  'snippet': {'text': f.snippet},
              },
            }
          }
        ],
        if (f.fingerprint != null)
          'partialFingerprints': {'checkScript/v1': f.fingerprint},
        // Correction concrète : suggestion applicable (GitHub Code Scanning,
        // IDE). Positions 1-based, colonne de fin exclusive, comme TextEdit.
        if (f.edits.isNotEmpty)
          'fixes': [
            {
              'description': {'text': f.hint ?? f.message},
              'artifactChanges': [
                {
                  'artifactLocation': {'uri': _uri(r.script.path)},
                  'replacements': [
                    for (final e in f.edits)
                      {
                        'deletedRegion': {
                          'startLine': e.line,
                          'startColumn': e.column,
                          'endLine': e.endLine,
                          'endColumn': e.endColumn,
                        },
                        'insertedContent': {'text': e.replacement},
                      }
                  ],
                }
              ],
            }
          ],
        'properties': {
          'severity': f.severity.name,
          'category': f.category.name,
          'tool': f.tool,
        },
      });
    }
  }

  return const JsonEncoder.withIndent('  ').convert({
    r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': 'check-script',
            'version': appVersion,
            'informationUri': 'https://github.com/chla28/CheckScript',
            'rules': rules.values.toList(),
          }
        },
        'results': results,
        'properties': {
          'scores': [
            for (final r in reports)
              {
                'file': r.script.path,
                'global': r.global,
                'grade': r.grade,
                for (final s in r.scores) s.category.name: s.score,
              }
          ],
        },
      }
    ],
  });
}
