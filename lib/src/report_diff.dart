/// Comparaison de deux rapports JSON de check-script (`check-script diff
/// AVANT.json APRÈS.json`, et fenêtre de comparaison de l'interface) :
/// problèmes nouveaux, corrigés et inchangés par script, évolution des
/// notes, scripts ajoutés ou retirés.
///
/// Les problèmes sont appariés par empreinte, comme pour la référence
/// (voir `baseline.dart`) : le numéro de ligne n'intervient pas.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'i18n.dart';
import 'json_num.dart';
import 'model/finding.dart';
import 'reporters/reporters.dart' show fmtScore;

/// Un problème lu dans un rapport JSON.
class DiffIssue {
  final String tool;
  final String rule;
  final Severity severity;
  final Category category;
  final int line;
  final String message;
  final String? fingerprint;

  const DiffIssue({
    required this.tool,
    required this.rule,
    required this.severity,
    required this.category,
    required this.line,
    required this.message,
    this.fingerprint,
  });

  factory DiffIssue.fromJson(Map<dynamic, dynamic> j) => DiffIssue(
        tool: '${j['tool'] ?? ''}',
        rule: '${j['rule'] ?? ''}',
        severity: Severity.tryParse('${j['severity']}') ?? Severity.low,
        category: Category.tryParse('${j['category']}') ?? Category.robustness,
        line: jsonInt(j['line']) ?? 0,
        message: '${j['message'] ?? ''}',
        fingerprint:
            j['fingerprint'] is String ? j['fingerprint'] as String : null,
      );

  Map<String, Object?> toJson() => {
        'tool': tool,
        'rule': rule,
        'severity': severity.name,
        'category': category.name,
        'line': line,
        'message': message,
      };
}

/// Comparaison d'un script présent dans les deux rapports.
class ScriptDiff {
  final String file;
  final double beforeGlobal;
  final double afterGlobal;
  final Map<Category, double> beforeScores;
  final Map<Category, double> afterScores;

  /// Problèmes apparus, disparus, présents dans les deux rapports (ces
  /// derniers dans leur version « après »).
  final List<DiffIssue> added;
  final List<DiffIssue> fixed;
  final List<DiffIssue> unchanged;

  const ScriptDiff({
    required this.file,
    required this.beforeGlobal,
    required this.afterGlobal,
    required this.beforeScores,
    required this.afterScores,
    required this.added,
    required this.fixed,
    required this.unchanged,
  });

  /// Écart de la note globale, arrondi au dixième.
  double get delta => ((afterGlobal - beforeGlobal) * 10).round() / 10;

  /// Tous les problèmes du rapport « avant » : disparus puis inchangés.
  List<DiffIssue> get before => [...fixed, ...unchanged];

  /// Tous les problèmes du rapport « après » : apparus puis inchangés.
  List<DiffIssue> get after => [...added, ...unchanged];

  Map<String, Object?> toJson() => {
        'file': file,
        'before': {'score': beforeGlobal},
        'after': {'score': afterGlobal},
        'delta': delta,
        'new': [for (final i in added) i.toJson()],
        'fixed': [for (final i in fixed) i.toJson()],
        'unchanged': unchanged.length,
      };
}

class ReportsDiff {
  /// Scripts présents dans les deux rapports.
  final List<ScriptDiff> scripts;

  /// Scripts présents seulement après / seulement avant.
  final List<String> addedScripts;
  final List<String> removedScripts;

  const ReportsDiff(this.scripts, this.addedScripts, this.removedScripts);

  int get newCount => scripts.fold(0, (n, s) => n + s.added.length);
  int get fixedCount => scripts.fold(0, (n, s) => n + s.fixed.length);
  int get unchangedCount => scripts.fold(0, (n, s) => n + s.unchanged.length);

  /// Note moyenne des scripts comparés, avant et après (0 sans script).
  double get beforeAverage => scripts.isEmpty
      ? 0
      : scripts.fold<double>(0, (a, s) => a + s.beforeGlobal) / scripts.length;
  double get afterAverage => scripts.isEmpty
      ? 0
      : scripts.fold<double>(0, (a, s) => a + s.afterGlobal) / scripts.length;

  /// Un problème nouveau atteint la sévérité [min] (ou plus grave).
  bool hasNew(Severity min) =>
      scripts.any((s) => s.added.any((i) => i.severity.index <= min.index));

  /// Une note globale a baissé (au dixième).
  bool get hasRegression => scripts.any((s) => s.delta < 0);

  Map<String, Object?> toJson() => {
        'tool': 'check-script',
        'summary': {
          'scripts': scripts.length,
          'addedScripts': addedScripts,
          'removedScripts': removedScripts,
          'new': newCount,
          'fixed': fixedCount,
          'unchanged': unchangedCount,
          'before': beforeAverage,
          'after': afterAverage,
        },
        'scripts': [for (final s in scripts) s.toJson()],
      };
}

class _Entry {
  _Entry(this.file, this.global, this.scores, this.issues);
  final String file;
  final double global;
  final Map<Category, double> scores;
  final List<DiffIssue> issues;
}

List<_Entry> _parse(String json, String name) {
  final Object? doc;
  try {
    doc = jsonDecode(json);
  } on FormatException {
    throw FormatException('$name: invalid JSON');
  }
  if (doc is! Map || doc['reports'] is! List) {
    throw FormatException(
        '$name: check-script JSON report expected ("reports" key)');
  }
  return [
    for (final r in (doc['reports'] as List).whereType<Map>())
      _Entry(
        '${r['file']}',
        jsonDouble((r['global'] as Map?)?['score']) ?? 0,
        {
          for (final c
              in (r['categories'] as List? ?? const []).whereType<Map>())
            if (Category.tryParse('${c['category']}') != null)
              Category.tryParse('${c['category']}')!:
                  jsonDouble(c['score']) ?? 0,
        },
        [
          for (final f in (r['findings'] as List? ?? const []).whereType<Map>())
            DiffIssue.fromJson(f)
        ],
      )
  ];
}

/// Compare deux rapports JSON ([beforeName] et [afterName] : noms utilisés
/// dans les messages d'erreur). Lève [FormatException] si l'un n'est pas un
/// rapport check-script.
ReportsDiff diffReports(String beforeJson, String afterJson,
    {String beforeName = 'before', String afterName = 'after'}) {
  final before = _parse(beforeJson, beforeName);
  final after = _parse(afterJson, afterName);

  // Apparie les scripts : même chemin, sinon même nom de fichier s'il est
  // unique de chaque côté.
  final unmatchedBefore = [...before];
  final pairs = <(_Entry, _Entry)>[];
  final addedScripts = <String>[];
  _Entry? take(String path) {
    for (final e in unmatchedBefore) {
      if (e.file == path || p.normalize(e.file) == p.normalize(path)) {
        unmatchedBefore.remove(e);
        return e;
      }
    }
    final same = unmatchedBefore
        .where((e) => p.basename(e.file) == p.basename(path))
        .toList();
    final afterSame =
        after.where((e) => p.basename(e.file) == p.basename(path)).length;
    if (same.length == 1 && afterSame == 1) {
      unmatchedBefore.remove(same.first);
      return same.first;
    }
    return null;
  }

  for (final a in after) {
    final b = take(a.file);
    if (b == null) {
      addedScripts.add(a.file);
    } else {
      pairs.add((b, a));
    }
  }

  final scripts = <ScriptDiff>[];
  for (final (b, a) in pairs) {
    // Multiensemble d'empreintes « avant » : chaque occurrence se consomme.
    final remaining = <String, List<DiffIssue>>{};
    for (final i in b.issues) {
      (remaining[i.fingerprint ?? '\u0000${i.rule}@${i.line}'] ??= []).add(i);
    }
    final added = <DiffIssue>[], unchanged = <DiffIssue>[];
    for (final i in a.issues) {
      final key = i.fingerprint ?? '\u0000${i.rule}@${i.line}';
      final left = remaining[key];
      if (left != null && left.isNotEmpty) {
        left.removeLast();
        unchanged.add(i);
      } else {
        added.add(i);
      }
    }
    final fixed = [for (final l in remaining.values) ...l]
      ..sort((x, y) => x.line.compareTo(y.line));
    scripts.add(ScriptDiff(
      file: a.file,
      beforeGlobal: b.global,
      afterGlobal: a.global,
      beforeScores: b.scores,
      afterScores: a.scores,
      added: added,
      fixed: fixed,
      unchanged: unchanged,
    ));
  }
  return ReportsDiff(
      scripts, addedScripts, [for (final e in unmatchedBefore) e.file]);
}

String _signed(double v, Lang lang) {
  final r = (v * 10).round() / 10;
  return '${r > 0 ? '+' : ''}${fmtScore(r, lang)}';
}

String _issueLine(String mark, DiffIssue i) =>
    '  $mark ${i.severity.label.padRight(8)} ${i.rule.padRight(8)} '
    '${i.line == 0 ? 'file' : 'L${i.line}'.padRight(4)}  ${i.message}';

/// Rapport texte de la comparaison. [details] : liste des problèmes
/// nouveaux (+) et corrigés (−) sous chaque script.
String renderDiffText(ReportsDiff d, Lang lang,
    {bool details = true, String before = 'before', String after = 'after'}) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  final m = Messages(lang);
  final b = StringBuffer()
    ..writeln(
        t('Comparaison : $before → $after', 'Comparison: $before → $after'))
    ..writeln(t(
        '${d.scripts.length} script(s) comparé(s), ${d.addedScripts.length} ajouté(s), '
            '${d.removedScripts.length} retiré(s) · note moyenne '
            '${fmtScore(d.beforeAverage, lang)} → ${fmtScore(d.afterAverage, lang)} '
            '(${_signed(d.afterAverage - d.beforeAverage, lang)})',
        '${d.scripts.length} script(s) compared, ${d.addedScripts.length} added, '
            '${d.removedScripts.length} removed · average score '
            '${fmtScore(d.beforeAverage, lang)} → ${fmtScore(d.afterAverage, lang)} '
            '(${_signed(d.afterAverage - d.beforeAverage, lang)})'))
    ..writeln(t(
        'Problèmes : ${d.newCount} nouveau(x) · ${d.fixedCount} corrigé(s) · '
            '${d.unchangedCount} inchangé(s)',
        'Issues: ${d.newCount} new · ${d.fixedCount} fixed · '
            '${d.unchangedCount} unchanged'));
  for (final s in d.scripts) {
    if (s.added.isEmpty && s.fixed.isEmpty && s.delta == 0) continue;
    b
      ..writeln()
      ..writeln('${s.file}  ${fmtScore(s.beforeGlobal, lang)} → '
          '${fmtScore(s.afterGlobal, lang)} (${_signed(s.delta, lang)})   '
          '${t('nouveaux', 'new')} ${s.added.length} · '
          '${t('corrigés', 'fixed')} ${s.fixed.length} · '
          '${t('inchangés', 'unchanged')} ${s.unchanged.length}');
    for (final c in Category.values) {
      final x = s.beforeScores[c], y = s.afterScores[c];
      if (x != null && y != null && ((y - x) * 10).round() != 0) {
        b.writeln('    ${m.category(c)}: ${fmtScore(x, lang)} → '
            '${fmtScore(y, lang)} (${_signed(y - x, lang)})');
      }
    }
    if (details) {
      for (final i in s.added) {
        b.writeln(_issueLine('+', i));
      }
      for (final i in s.fixed) {
        b.writeln(_issueLine('−', i));
      }
    }
  }
  if (d.addedScripts.isNotEmpty) {
    b
      ..writeln()
      ..writeln(t('Scripts ajoutés :', 'Added scripts:'));
    for (final f in d.addedScripts) {
      b.writeln('  + $f');
    }
  }
  if (d.removedScripts.isNotEmpty) {
    b
      ..writeln()
      ..writeln(t('Scripts retirés :', 'Removed scripts:'));
    for (final f in d.removedScripts) {
      b.writeln('  − $f');
    }
  }
  return b.toString();
}

/// Comparaison en Markdown (commentaire de merge request).
String renderDiffMarkdown(ReportsDiff d, Lang lang,
    {String before = 'before', String after = 'after'}) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  final b = StringBuffer()
    ..writeln(
        '## ${t('Évolution de la qualité des scripts', 'Script quality evolution')}')
    ..writeln()
    ..writeln(t(
        'Note moyenne : **${fmtScore(d.beforeAverage, lang)} → ${fmtScore(d.afterAverage, lang)}** '
            '(${_signed(d.afterAverage - d.beforeAverage, lang)}) · '
            '${d.newCount} nouveau(x), ${d.fixedCount} corrigé(s), ${d.unchangedCount} inchangé(s)',
        'Average score: **${fmtScore(d.beforeAverage, lang)} → ${fmtScore(d.afterAverage, lang)}** '
            '(${_signed(d.afterAverage - d.beforeAverage, lang)}) · '
            '${d.newCount} new, ${d.fixedCount} fixed, ${d.unchangedCount} unchanged'))
    ..writeln();
  final changed = [
    for (final s in d.scripts)
      if (s.added.isNotEmpty || s.fixed.isNotEmpty || s.delta != 0) s
  ];
  if (changed.isNotEmpty) {
    b
      ..writeln('| ${t('Script', 'Script')} | ${t('Note', 'Score')} | '
          '${t('Nouveaux', 'New')} | ${t('Corrigés', 'Fixed')} |')
      ..writeln('|---|---|---:|---:|');
    for (final s in changed) {
      b.writeln('| `${s.file}` | ${fmtScore(s.beforeGlobal, lang)} → '
          '${fmtScore(s.afterGlobal, lang)} (${_signed(s.delta, lang)}) | '
          '${s.added.length} | ${s.fixed.length} |');
    }
    final news = [
      for (final s in changed)
        for (final i in s.added) (s.file, i)
    ];
    if (news.isNotEmpty) {
      b
        ..writeln()
        ..writeln('### ${t('Nouveaux problèmes', 'New issues')}')
        ..writeln();
      for (final (f, i) in news) {
        b.writeln('- **${i.severity.label}** `${i.rule}` — `$f`'
            '${i.line == 0 ? '' : ':${i.line}'} — ${i.message}');
      }
    }
  }
  for (final f in d.addedScripts) {
    b.writeln('\n${t('Script ajouté', 'Added script')} : `$f`');
  }
  for (final f in d.removedScripts) {
    b.writeln('\n${t('Script retiré', 'Removed script')} : `$f`');
  }
  return b.toString();
}

/// Comparaison en JSON.
String renderDiffJson(ReportsDiff d) =>
    const JsonEncoder.withIndent('  ').convert(d.toJson());
