/// Rapport PDF, livrable d'audit : page de garde (périmètre, note moyenne,
/// problèmes par sévérité), synthèse des scripts, référentiels (CWE, OWASP,
/// ANSSI), paquets à installer, puis détail par script.
///
/// Police : une police TrueType du système (Noto Sans, DejaVu Sans,
/// Liberation Sans, Bitstream Vera… et leur variante à chasse fixe) ; à
/// défaut, les polices standard du PDF (Helvetica, Courier), les caractères
/// qu'elles ne couvrent pas étant remplacés (→ devient ->).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../analyzers/commands.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../model/report.dart';
import '../rules/references.dart';
import '../scoring.dart';
import '../version.dart';
import 'reporters.dart' show RenderOptions, fmtScore;

/// Polices du rapport ; null : police standard du PDF.
class PdfFonts {
  final pw.Font? regular, bold, italic, mono;
  const PdfFonts({this.regular, this.bold, this.italic, this.mono});

  /// Polices standard seulement (latin-1).
  static const standard = PdfFonts();

  bool get unicode => regular != null;

  /// Emplacements usuels (Fedora/RHEL, Debian/Ubuntu) des polices TrueType.
  static const _candidates = [
    (
      '/usr/share/fonts/google-noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/google-noto/NotoSans-Bold.ttf',
      '/usr/share/fonts/google-noto/NotoSans-Italic.ttf',
    ),
    (
      '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
      '/usr/share/fonts/truetype/noto/NotoSans-Italic.ttf',
    ),
    (
      '/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf',
      '/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Oblique.ttf',
    ),
    (
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf',
    ),
    (
      '/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf',
      '/usr/share/fonts/liberation-sans-fonts/LiberationSans-Bold.ttf',
      '/usr/share/fonts/liberation-sans-fonts/LiberationSans-Italic.ttf',
    ),
    (
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Italic.ttf',
    ),
    (
      '/usr/share/fonts/bitstream-vera-sans-fonts/Vera.ttf',
      '/usr/share/fonts/bitstream-vera-sans-fonts/VeraBd.ttf',
      '/usr/share/fonts/bitstream-vera-sans-fonts/VeraIt.ttf',
    ),
  ];

  static const _monoCandidates = [
    '/usr/share/fonts/google-noto/NotoSansMono-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf',
    '/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/liberation-mono-fonts/LiberationMono-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf',
    '/usr/share/fonts/bitstream-vera-sans-mono-fonts/VeraMono.ttf',
  ];

  static pw.Font? _load(String? path) {
    if (path == null) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    try {
      return pw.Font.ttf(ByteData.sublistView(f.readAsBytesSync()));
    } on Object {
      return null;
    }
  }

  /// Première famille complète trouvée sur le système.
  static PdfFonts system() {
    for (final (r, b, i) in _candidates) {
      final regular = _load(r);
      if (regular == null) continue;
      return PdfFonts(
        regular: regular,
        bold: _load(b) ?? regular,
        italic: _load(i) ?? regular,
        mono: _monoCandidates
            .map(_load)
            .firstWhere((f) => f != null, orElse: () => null),
      );
    }
    return standard;
  }
}

/// Texte affichable par les polices standard (latin-1) : quelques
/// équivalents, sinon « ? ».
String latin1Safe(String s) {
  const map = {
    '→': '->', '←': '<-', '…': '...', '—': '-', '–': '-', '’': "'", //
    '‘': "'", '“': '"', '”': '"', 'œ': 'oe', 'Œ': 'OE', '✗': 'x',
    '✓': 'v', '▶': '>', '•': '-', '≤': '<=', '≥': '>=', '×': 'x',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (r < 0x100) {
      b.write(c);
    } else {
      b.write(map[c] ?? '?');
    }
  }
  return b.toString();
}

/// Flèches et symboles absents de nombreuses polices texte (Noto Sans,
/// DejaVu…) : remplacés même avec une police Unicode.
String unicodeSafe(String s) {
  const map = {
    '→': '->', '←': '<-', '≥': '>=', '≤': '<=', '✗': 'x', '✓': 'v', //
    '▶': '>',
  };
  var out = s;
  map.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}

PdfColor _severityColor(Severity s) => switch (s) {
      Severity.critical => PdfColor.fromHex('#b3261e'),
      Severity.high => PdfColor.fromHex('#d9480f'),
      Severity.medium => PdfColor.fromHex('#b8860b'),
      Severity.low => PdfColor.fromHex('#2f6fb5'),
    };

PdfColor _scoreColor(double v) => v >= 7.5
    ? PdfColor.fromHex('#2e7d32')
    : (v >= 5 ? PdfColor.fromHex('#b8860b') : PdfColor.fromHex('#b3261e'));

final _muted = PdfColor.fromHex('#6b6b70');
final _line = PdfColor.fromHex('#d4d4d8');
final _head = PdfColor.fromHex('#f0f0f2');

/// Rapport PDF de [reports] ; [fonts] par défaut : polices du système.
Future<Uint8List> renderPdf(List<ScriptReport> reports, RenderOptions o,
    {PdfFonts? fonts}) async {
  final f = fonts ?? PdfFonts.system();
  try {
    return await _build(reports, o, f);
  } on Object {
    // Police refusée par le moteur PDF : polices standard.
    if (f.unicode) return _build(reports, o, PdfFonts.standard);
    rethrow;
  }
}

Future<Uint8List> _build(
    List<ScriptReport> reports, RenderOptions o, PdfFonts fonts) {
  final t = Messages(o.lang);
  final fr = o.lang == Lang.fr;
  String tx(String s) => fonts.unicode ? unicodeSafe(s) : latin1Safe(s);
  final base = fonts.regular ?? pw.Font.helvetica();
  final bold = fonts.bold ?? pw.Font.helveticaBold();
  final italic = fonts.italic ?? pw.Font.helveticaOblique();
  final mono = fonts.mono ?? pw.Font.courier();
  final doc = pw.Document(
    title: tx(fr ? 'Rapport d\'audit des scripts' : 'Script audit report'),
    creator: 'check-script $appVersion',
    producer: 'check-script $appVersion',
    theme: pw.ThemeData.withFont(
        base: base, bold: bold, italic: italic, boldItalic: bold),
  );
  final now = DateTime.now();
  final date = '${now.year}-${_two(now.month)}-${_two(now.day)} '
      '${_two(now.hour)}:${_two(now.minute)}';
  final avg = reports.isEmpty
      ? 0.0
      : reports.map((r) => r.global).reduce((a, b) => a + b) / reports.length;
  final bySev = {
    for (final s in Severity.values)
      s: reports.fold<int>(
          0, (n, r) => n + r.findings.where((x) => x.severity == s).length)
  };

  pw.Widget text(String s,
          {double size = 9,
          pw.Font? font,
          PdfColor? color,
          pw.FontWeight? weight}) =>
      pw.Text(tx(s),
          style: pw.TextStyle(
              fontSize: size, font: font, color: color, fontWeight: weight));

  pw.Widget cell(String s,
          {double size = 8,
          pw.Font? font,
          PdfColor? color,
          bool strong = false}) =>
      pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: text(s,
              size: size, font: font ?? (strong ? bold : null), color: color));

  pw.TableRow headRow(List<String> cols) => pw.TableRow(
      decoration: pw.BoxDecoration(color: _head),
      children: [for (final c in cols) cell(c, strong: true)]);

  pw.Widget table(List<String> head, List<pw.TableRow> rows,
          Map<int, pw.TableColumnWidth> widths) =>
      pw.Table(
          border: pw.TableBorder.all(color: _line, width: .5),
          columnWidths: widths,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [headRow(head), ...rows]);

  pw.Widget heading(String s, {double size = 14}) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
      child: text(s, size: size, font: bold));

  // ── Page de garde ────────────────────────────────────────────────────────
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(48),
    build: (_) =>
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(height: 80),
      text(fr ? 'Rapport d\'audit des scripts' : 'Script audit report',
          size: 26, font: bold),
      pw.SizedBox(height: 6),
      text('check-script $appVersion · $date', size: 11, color: _muted),
      pw.SizedBox(height: 40),
      text(
          fr
              ? '${reports.length} script(s) analysé(s)'
              : '${reports.length} script(s) analysed',
          size: 13),
      if (reports.isNotEmpty)
        text(
            '${t.profile}${t.colon}${reports.first.profile}'
            '${reports.first.contexts.isEmpty ? '' : ' · ${t.contexts}${t.colon}${reports.first.contexts.join(', ')}'}',
            size: 11,
            color: _muted),
      pw.SizedBox(height: 30),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        text(fmtScore(avg, o.lang),
            size: 48, font: bold, color: _scoreColor(avg)),
        pw.SizedBox(width: 6),
        text('/10  (${gradeFor(avg)})', size: 18, color: _muted),
      ]),
      text(
          fr
              ? (reports.length > 1 ? 'Note moyenne' : 'Note globale')
              : (reports.length > 1 ? 'Average score' : 'Global score'),
          size: 11,
          color: _muted),
      pw.SizedBox(height: 30),
      pw.Row(children: [
        for (final s in Severity.values)
          pw.Container(
            width: 90,
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _severityColor(s), width: 1),
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(children: [
              text('${bySev[s]}',
                  size: 20, font: bold, color: _severityColor(s)),
              text(s.label, size: 9, color: _severityColor(s)),
            ]),
          ),
      ]),
      pw.Spacer(),
      text(
          fr
              ? 'Notes sur 10 par catégorie (Sécurité, Robustesse, Maintenabilité, Portabilité, Performance) ; niveaux A (≥ 9) à E. Références : CWE (MITRE), OWASP Top 10 2021 et CI/CD, ANSSI.'
              : 'Scores out of 10 per category (Security, Robustness, Maintainability, Portability, Performance); grades A (≥ 9) to E. References: CWE (MITRE), OWASP Top 10 2021 and CI/CD, ANSSI.',
          size: 8,
          color: _muted),
    ]),
  ));

  // ── Corps ────────────────────────────────────────────────────────────────
  final body = <pw.Widget>[];

  // Synthèse des scripts.
  body.add(heading(fr ? 'Synthèse' : 'Summary'));
  body.add(table([
    'Script',
    fr ? 'Note' : 'Score',
    fr ? 'Niveau' : 'Grade',
    for (final s in Severity.values) s.label.substring(0, 1),
  ], [
    for (final r in [...reports]..sort((a, b) => a.global.compareTo(b.global)))
      pw.TableRow(children: [
        cell(r.script.path, font: mono),
        cell(fmtScore(r.global, o.lang), color: _scoreColor(r.global)),
        cell(r.grade, strong: true),
        for (final s in Severity.values)
          cell('${r.findings.where((x) => x.severity == s).length}',
              color: _severityColor(s)),
      ]),
  ], {
    0: const pw.FlexColumnWidth(),
    1: const pw.FixedColumnWidth(34),
    2: const pw.FixedColumnWidth(34),
    for (var i = 3; i < 7; i++) i: const pw.FixedColumnWidth(22),
  }));

  // Référentiels.
  final count = <String, int>{};
  final worst = <String, Severity>{};
  final scripts = <String, Set<String>>{};
  for (final r in reports) {
    for (final x in r.findings) {
      for (final ref in x.refs) {
        count[ref] = (count[ref] ?? 0) + 1;
        final w = worst[ref];
        if (w == null || x.severity.index < w.index) worst[ref] = x.severity;
        (scripts[ref] ??= {}).add(r.script.path);
      }
    }
  }
  if (count.isNotEmpty) {
    body.add(heading(t.references));
    body.add(text(t.referencesIntro, size: 8, color: _muted));
    body.add(pw.SizedBox(height: 4));
    body.add(table([
      t.reference,
      t.message,
      t.issuesCount,
      t.worstSeverity,
      t.scriptsCount,
    ], [
      for (final ref in sortReferences(count.keys))
        pw.TableRow(children: [
          cell(ref, strong: true),
          cell(referenceTitles[ref] ?? ''),
          cell('${count[ref]}'),
          cell(worst[ref]!.label, color: _severityColor(worst[ref]!)),
          cell('${scripts[ref]!.length}'),
        ]),
    ], {
      0: const pw.FixedColumnWidth(96),
      1: const pw.FlexColumnWidth(),
      2: const pw.FixedColumnWidth(48),
      3: const pw.FixedColumnWidth(52),
      4: const pw.FixedColumnWidth(40),
    }));
  }

  // Paquets à installer.
  final (dnf, apt) = requiredPackages([for (final r in reports) ...r.commands]);
  if (dnf.isNotEmpty || apt.isNotEmpty) {
    body.add(heading(t.packagesToInstall));
    body.add(text('dnf install ${dnf.join(' ')}', size: 8, font: mono));
    body.add(text('apt install ${apt.join(' ')}', size: 8, font: mono));
  }

  // Détail par script.
  for (final r in reports) {
    body.add(pw.NewPage());
    body.add(heading(r.script.path, size: 13));
    body.add(text(
        '${t.dialect}${t.colon}${r.script.dialectLabel} · '
        '${t.lines}${t.colon}${t.linesDetail(r.script.totalLines, r.script.codeLines, r.script.commentLines)}',
        size: 8,
        color: _muted));
    body.add(text(
        '${t.tools}${t.colon}${[
          for (final run in r.tools)
            '${run.tool}${run.version != null ? ' ${run.version}' : ''} (${t.toolStatus(run.status)})'
        ].join(', ')}',
        size: 7,
        color: _muted));
    body.add(pw.SizedBox(height: 6));
    body.add(pw.Row(children: [
      text(fmtScore(r.global, o.lang),
          size: 22, font: bold, color: _scoreColor(r.global)),
      text(' /10 (${r.grade})', size: 12, color: _muted),
    ]));
    body.add(pw.SizedBox(height: 4));
    body.add(table([
      fr ? 'Catégorie' : 'Category',
      fr ? 'Note' : 'Score',
      for (final s in Severity.values) s.label,
    ], [
      for (final c in Category.values)
        pw.TableRow(children: [
          cell(t.category(c)),
          cell(fmtScore(r.score(c).score, o.lang),
              color: _scoreColor(r.score(c).score)),
          for (final s in Severity.values)
            cell(
                '${r.findings.where((x) => x.category == c && x.severity == s).length}'),
        ]),
    ], {
      0: const pw.FlexColumnWidth(),
      for (var i = 1; i < 6; i++) i: const pw.FixedColumnWidth(48),
    }));

    if (r.commands.isNotEmpty) {
      body.add(heading(t.commands, size: 11));
      body.add(table([
        t.command,
        t.lines_,
        t.present,
        'dnf',
        'apt'
      ], [
        for (final u in r.commands)
          pw.TableRow(children: [
            cell(u.name, font: mono),
            cell(u.lines.join(', ')),
            cell(
                switch (u.found) {
                  true => t.yes,
                  false => u.checked ? '${t.no} (${t.checkedByScript})' : t.no,
                  null => t.unknown,
                },
                color: u.found == false ? _severityColor(Severity.high) : null),
            cell(u.dnf ?? ''),
            cell(u.apt ?? ''),
          ]),
      ], {
        0: const pw.FlexColumnWidth(),
        1: const pw.FixedColumnWidth(70),
        2: const pw.FixedColumnWidth(80),
        3: const pw.FixedColumnWidth(80),
        4: const pw.FixedColumnWidth(80),
      }));
    }

    body.add(heading(t.details, size: 11));
    if (r.findings.isEmpty) {
      body.add(text(t.noIssue));
      continue;
    }
    body.add(table([
      fr ? 'Ligne' : 'Line',
      t.severity,
      t.rule,
      t.message,
    ], [
      for (final x in r.findings)
        pw.TableRow(children: [
          cell(x.line == 0 ? '—' : '${x.line}'),
          cell(x.severity.label,
              color: _severityColor(x.severity), strong: true),
          pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    text(x.ruleId, size: 8, font: bold),
                    text(x.tool, size: 7, color: _muted),
                  ])),
          pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    text(x.message, size: 8),
                    if (x.snippet != null && x.snippet!.trim().isNotEmpty)
                      text(x.snippet!.trim(),
                          size: 7, font: mono, color: _muted),
                    if (x.hint != null)
                      text('→ ${x.hint}', size: 7, font: italic),
                    if (x.refs.isNotEmpty)
                      text(x.refs.join(' · '), size: 6.5, color: _muted),
                  ])),
        ]),
    ], {
      0: const pw.FixedColumnWidth(30),
      1: const pw.FixedColumnWidth(46),
      2: const pw.FixedColumnWidth(72),
      3: const pw.FlexColumnWidth(),
    }));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
    maxPages: 1000,
    header: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(bottom: 6),
        child: text(
            fr
                ? 'CheckScript — rapport d\'audit · $date'
                : 'CheckScript — audit report · $date',
            size: 7,
            color: _muted)),
    footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: text('${ctx.pageNumber} / ${ctx.pagesCount}',
            size: 7, color: _muted)),
    build: (_) => body,
  ));
  return doc.save();
}

String _two(int v) => v.toString().padLeft(2, '0');
