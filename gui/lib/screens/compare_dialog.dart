/// Comparaison de deux analyses, côte à côte : à gauche l'état « avant »
/// (problèmes corrigés en vert), à droite l'état « après » (problèmes
/// nouveaux en rouge). « Avant » : un rapport JSON (ou la référence
/// chargée) ; « après » : l'analyse affichée ou un autre rapport JSON.
/// Même moteur de comparaison que `check-script diff`.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../help/tips.dart';
import '../widgets/common.dart';

/// Ouvre la comparaison en plein écran. [folder] : « après » est l'analyse du
/// dossier plutôt que celle du script affiché.
Future<void> showCompareDialog(BuildContext context, AppState state,
    {bool folder = false, PickedReport? before, PickedReport? after}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (ctx) => Dialog.fullscreen(
      child: CompareView(
          state: state,
          folder: folder,
          initialBefore: before,
          initialAfter: after),
    ),
  );
}

/// Un rapport choisi : nom affiché et contenu JSON.
typedef PickedReport = ({String name, String json});

class CompareView extends StatefulWidget {
  const CompareView({
    super.key,
    required this.state,
    this.folder = false,
    this.initialBefore,
    this.initialAfter,
  });
  final AppState state;
  final bool folder;

  /// Rapports déjà choisis (tests, ou reprise).
  final PickedReport? initialBefore;
  final PickedReport? initialAfter;

  @override
  State<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<CompareView> {
  PickedReport? _before;
  PickedReport? _afterFile;

  /// « Après » : l'analyse affichée (sinon [_afterFile]).
  late bool _afterIsCurrent = widget.initialAfter == null;
  ReportsDiff? _diff;
  String? _error;
  String? _selected;
  bool _showUnchanged = false;

  AppState get state => widget.state;
  Lang get lang => state.lang;
  String t(String fr, String en) => lang == Lang.fr ? fr : en;

  @override
  void initState() {
    super.initState();
    _before = widget.initialBefore;
    _afterFile = widget.initialAfter;
    _recompute();
  }

  /// « Après » courant : l'analyse affichée en JSON, ou le fichier choisi.
  PickedReport? get _after {
    if (!_afterIsCurrent) return _afterFile;
    final reports = widget.folder
        ? state.folderReports
        : [if (state.current != null) state.current!];
    if (reports.isEmpty) return null;
    return (
      name: widget.folder
          ? t('dossier analysé', 'analysed folder')
          : p.basename(reports.single.script.path),
      json: renderJson(reports),
    );
  }

  void _recompute() {
    final before = _before, after = _after;
    if (before == null || after == null) {
      setState(() {
        _diff = null;
        _error = null;
      });
      return;
    }
    try {
      final d = diffReports(before.json, after.json,
          beforeName: before.name, afterName: after.name);
      setState(() {
        _diff = d;
        _error = null;
        _selected = _ordered(d).firstOrNull?.file;
      });
    } on FormatException catch (e) {
      setState(() {
        _diff = null;
        _error = e.message;
      });
    }
  }

  /// Scripts comparés : régressions d'abord, puis ceux qui ont des problèmes
  /// nouveaux, puis les autres.
  static List<ScriptDiff> _ordered(ReportsDiff d) =>
      [...d.scripts]..sort((a, b) {
          int rank(ScriptDiff s) => s.delta < 0
              ? 0
              : (s.added.isNotEmpty ? 1 : (s.fixed.isNotEmpty ? 2 : 3));
          final r = rank(a).compareTo(rank(b));
          return r != 0 ? r : a.delta.compareTo(b.delta);
        });

  Future<PickedReport?> _pick(String title) async {
    final r = await FilePicker.pickFiles(
        dialogTitle: title, type: FileType.custom, allowedExtensions: ['json']);
    final path = r?.files.single.path;
    if (path == null) return null;
    try {
      return (name: p.basename(path), json: await File(path).readAsString());
    } on FileSystemException {
      setState(() =>
          _error = t('Rapport illisible : $path', 'Unreadable report: $path'));
      return null;
    }
  }

  Future<void> _loadBaseline() async {
    final path = state.baselinePath;
    if (path == null) return;
    try {
      _before = (name: p.basename(path), json: await File(path).readAsString());
      _recompute();
    } on FileSystemException {
      setState(() =>
          _error = t('Rapport illisible : $path', 'Unreadable report: $path'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tp = Tips(lang);
    final d = _diff;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Comparer deux analyses', 'Compare two analyses')),
        leading: IconButton(
          tooltip: t('Fermer', 'Close'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (d != null)
            tip(
              tp.copyDiff,
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: Text(t('Copier (Markdown)', 'Copy (Markdown)')),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  await Clipboard.setData(ClipboardData(
                      text: renderDiffMarkdown(d, lang,
                          before: _before!.name, after: _after!.name)));
                  messenger?.showSnackBar(SnackBar(
                      content: Text(
                          t('Comparaison copiée.', 'Comparison copied.'))));
                },
              ),
            ),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 24,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _side(
                t('Avant', 'Before'),
                [
                  tip(
                    tp.pickReport,
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: Text(_before?.name ??
                          t('Choisir un rapport JSON…', 'Pick a JSON report…')),
                      onPressed: () async {
                        final r = await _pick(
                            t('Rapport « avant »', '“Before” report'));
                        if (r != null) {
                          _before = r;
                          _recompute();
                        }
                      },
                    ),
                  ),
                  if (state.baselinePath != null)
                    tip(
                      tp.useBaseline,
                      ActionChip(
                        avatar: const Icon(Icons.compare_arrows, size: 18),
                        label: Text(t('Référence chargée', 'Loaded baseline')),
                        onPressed: _loadBaseline,
                      ),
                    ),
                ],
              ),
              _side(
                t('Après', 'After'),
                [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: true,
                          label: Text(widget.folder
                              ? t('Dossier analysé', 'Analysed folder')
                              : t('Analyse affichée', 'Displayed analysis'))),
                      ButtonSegment(
                          value: false,
                          label: Text(_afterFile?.name ??
                              t('Fichier JSON…', 'JSON file…'))),
                    ],
                    selected: {_afterIsCurrent},
                    onSelectionChanged: (v) async {
                      if (v.first) {
                        _afterIsCurrent = true;
                        _recompute();
                      } else {
                        final r = await _pick(
                            t('Rapport « après »', '“After” report'));
                        if (r != null) {
                          _afterFile = r;
                          _afterIsCurrent = false;
                          _recompute();
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ))
              : d == null
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          t('Choisissez le rapport « avant » : l\'analyse affichée est comparée à lui.',
                              'Pick the “before” report: the displayed analysis is compared to it.'),
                          textAlign: TextAlign.center),
                    ))
                  : _result(context, d),
        ),
      ]),
    );
  }

  Widget _side(String label, List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        Wrap(spacing: 8, children: children),
      ]);

  Widget _result(BuildContext context, ReportsDiff d) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final scripts = _ordered(d);
    final sel = scripts.where((s) => s.file == _selected).firstOrNull;
    final delta = ((d.afterAverage - d.beforeAverage) * 10).round() / 10;
    Widget summary() => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                    '${t('Note moyenne', 'Average score')} '
                    '${fmtScore(d.beforeAverage, lang)} → ${fmtScore(d.afterAverage, lang)}',
                    style: theme.textTheme.titleMedium),
                DeltaChip(d.afterAverage, d.beforeAverage, lang),
                _count(
                    t('nouveaux', 'new'),
                    d.newCount,
                    d.newCount > 0
                        ? severityColor(Severity.critical, b)
                        : null),
                _count(t('corrigés', 'fixed'), d.fixedCount,
                    d.fixedCount > 0 ? scoreColor(10, b) : null),
                _count(t('inchangés', 'unchanged'), d.unchangedCount, null),
                if (d.addedScripts.isNotEmpty)
                  Text(t('${d.addedScripts.length} script(s) ajouté(s)',
                      '${d.addedScripts.length} script(s) added')),
                if (d.removedScripts.isNotEmpty)
                  Text(t('${d.removedScripts.length} script(s) retiré(s)',
                      '${d.removedScripts.length} script(s) removed')),
                if (delta == 0 && d.newCount == 0 && d.fixedCount == 0)
                  Text(t('Aucune différence.', 'No difference.'),
                      style: theme.textTheme.bodyMedium),
              ]),
        );

    final list = ListView(children: [
      for (final s in scripts)
        ListTile(
          dense: true,
          selected: s.file == _selected,
          title: Text(p.basename(s.file), overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${fmtScore(s.beforeGlobal, lang)} → ${fmtScore(s.afterGlobal, lang)} '
              '(${fmtDelta(s.afterGlobal, s.beforeGlobal, lang)}) · '
              '+${s.added.length} −${s.fixed.length}'),
          trailing: s.delta < 0
              ? Icon(Icons.trending_down,
                  size: 18, color: severityColor(Severity.critical, b))
              : (s.delta > 0
                  ? Icon(Icons.trending_up, size: 18, color: scoreColor(10, b))
                  : null),
          onTap: () => setState(() => _selected = s.file),
        ),
      for (final f in d.addedScripts)
        ListTile(
            dense: true,
            leading: const Icon(Icons.add, size: 18),
            title: Text(p.basename(f)),
            subtitle: Text(t('ajouté', 'added'))),
      for (final f in d.removedScripts)
        ListTile(
            dense: true,
            leading: const Icon(Icons.remove, size: 18),
            title: Text(p.basename(f)),
            subtitle: Text(t('retiré', 'removed'))),
    ]);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final detail =
          sel == null ? const SizedBox.shrink() : _sideBySide(context, sel);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        summary(),
        const Divider(height: 1),
        Expanded(
          child: wide
              ? Row(children: [
                  SizedBox(width: 300, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(child: detail),
                ])
              : Column(children: [
                  SizedBox(height: 150, child: list),
                  const Divider(height: 1),
                  Expanded(child: detail),
                ]),
        ),
      ]);
    });
  }

  Widget _count(String label, int n, Color? color) => Chip(
        visualDensity: VisualDensity.compact,
        side: color == null ? null : BorderSide(color: color),
        label: Text('$n $label',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      );

  Widget _sideBySide(BuildContext context, ScriptDiff s) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final m = Messages(lang);
    Widget column(String title, double score, List<(DiffIssue, int)> rows) =>
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: theme.colorScheme.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('$title — ${fmtScore(score, lang)}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: scoreColor(score, b))),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(t('Aucun problème.', 'No issue.')))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) =>
                          _issueTile(rows[i].$1, rows[i].$2, b),
                    ),
            ),
          ]),
        );

    // 0 : inchangé, 1 : corrigé (colonne « avant »), 2 : nouveau (« après »).
    List<(DiffIssue, int)> rows(List<DiffIssue> only, int mark) => [
          for (final i in only) (i, mark),
          if (_showUnchanged)
            for (final i in s.unchanged) (i, 0),
        ]..sort((x, y) => x.$1.line.compareTo(y.$1.line));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(p.basename(s.file), style: theme.textTheme.titleSmall),
              for (final c in Category.values)
                if (s.beforeScores[c] != null &&
                    s.afterScores[c] != null &&
                    ((s.afterScores[c]! - s.beforeScores[c]!) * 10).round() !=
                        0)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                        '${m.category(c)} ${fmtScore(s.beforeScores[c]!, lang)} → ${fmtScore(s.afterScores[c]!, lang)}'),
                  ),
              FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text(t('Inchangés (${s.unchanged.length})',
                    'Unchanged (${s.unchanged.length})')),
                selected: _showUnchanged,
                onSelected: (v) => setState(() => _showUnchanged = v),
              ),
            ]),
      ),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          column(t('Avant', 'Before'), s.beforeGlobal, rows(s.fixed, 1)),
          const VerticalDivider(width: 1),
          column(t('Après', 'After'), s.afterGlobal, rows(s.added, 2)),
        ]),
      ),
    ]);
  }

  Widget _issueTile(DiffIssue i, int mark, Brightness b) {
    final theme = Theme.of(context);
    final Color? tint = switch (mark) {
      1 => scoreColor(10, b).withValues(alpha: 0.14),
      2 => severityColor(Severity.critical, b).withValues(alpha: 0.12),
      _ => null,
    };
    final markLabel = switch (mark) {
      1 => t('corrigé', 'fixed'),
      2 => t('nouveau', 'new'),
      _ => null,
    };
    return Semantics(
      label: [
        if (markLabel != null) markLabel,
        i.severity.label,
        i.rule,
        i.message
      ].join(', '),
      child: Container(
        color: tint,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SeverityBadge(i.severity),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.message, style: theme.textTheme.bodySmall),
              Text(
                  '${i.rule} · ${i.line == 0 ? t('fichier entier', 'whole file') : 'L${i.line}'}',
                  style: theme.textTheme.labelSmall),
            ]),
          ),
          if (markLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                  mark == 1
                      ? Icons.check_circle_outline
                      : Icons.add_circle_outline,
                  size: 18,
                  color: mark == 1
                      ? scoreColor(10, b)
                      : severityColor(Severity.critical, b)),
            ),
        ]),
      ),
    );
  }
}
