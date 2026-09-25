/// Écran d'analyse d'un script : source annotée à gauche, notes et problèmes
/// à droite ; actions ouvrir, relancer, corriger, exporter, référence.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../editor.dart';
import '../strings.dart';
import '../widgets/findings_list.dart';
import '../widgets/score_panel.dart';
import '../widgets/source_view.dart';
import '../widgets/split_view.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.state});
  final AppState state;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  int? _selectedLine;

  AppState get state => widget.state;

  Future<void> _open() async {
    final r = await FilePicker.pickFiles(dialogTitle: S(state.lang).openScript);
    final path = r?.files.single.path;
    if (path != null) await state.analyzeFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final report = state.current;
    return LayoutBuilder(
        builder: (context, outer) => Column(children: [
              // Barre d'outils : au plus 40 % de la hauteur, défilante au-delà
              // (fenêtre basse et étroite : les boutons passent sur plusieurs lignes).
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: outer.maxHeight * 0.4),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                              onPressed: state.busy ? null : _open,
                              icon: const Icon(Icons.file_open),
                              label: Text(s.openScript)),
                          OutlinedButton.icon(
                              onPressed: state.busy || report == null
                                  ? null
                                  : state.reanalyze,
                              icon: const Icon(Icons.refresh),
                              label: Text(s.reanalyze)),
                          OutlinedButton.icon(
                              onPressed: state.busy || report == null
                                  ? null
                                  : () => _fix(context),
                              icon: const Icon(Icons.auto_fix_high),
                              label: Text(s.fix)),
                          OutlinedButton.icon(
                              onPressed: report == null
                                  ? null
                                  : () =>
                                      exportReports(context, state, [report]),
                              icon: const Icon(Icons.save_alt),
                              label: Text(s.export)),
                          OutlinedButton.icon(
                              onPressed: report == null ||
                                      report.script.path == '<stdin>'
                                  ? null
                                  : () => _edit(context, report.script.path,
                                      _selectedLine ?? 1),
                              icon: const Icon(Icons.edit_note),
                              label: Text(s.openInEditor)),
                          BaselineButton(state: state),
                          if (report != null)
                            Text(report.script.path,
                                style: Theme.of(context).textTheme.bodySmall),
                        ]),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: report == null
                    ? Center(
                        child: Text(s.dropHere, textAlign: TextAlign.center))
                    : LayoutBuilder(builder: (context, c) {
                        final issues = detailFindings(report);
                        final side = DefaultTabController(
                          length: 2,
                          child: Column(children: [
                            TabBar(tabs: [
                              Tab(text: s.summary),
                              Tab(text: '${s.issues} (${issues.length})'),
                            ]),
                            Expanded(
                              child: TabBarView(children: [
                                SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: ScorePanel(
                                      report: report, lang: state.lang),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: FindingsList(
                                    findings: issues,
                                    lang: state.lang,
                                    lines: report.script.displayLines,
                                    onSelect: (f) =>
                                        setState(() => _selectedLine = f.line),
                                    onApplyFix: state.busy
                                        ? null
                                        : (f) => _applyOne(context, f),
                                    onDisableRule: (f) =>
                                        _disableRule(context, f),
                                    onApplyRule: state.busy
                                        ? null
                                        : (f) => _applyRule(context, f),
                                    onApplySelection: state.busy
                                        ? null
                                        : (fs) => _applySelection(context, fs),
                                    explanation: report.explanation,
                                    onOpenInEditor: (f) => _edit(
                                        context, report.script.path, f.line),
                                    onReportFalsePositive: state
                                                .falsePositives ==
                                            null
                                        ? null
                                        : (f) =>
                                            _falsePositive(context, report, f),
                                  ),
                                ),
                              ]),
                            ),
                          ]),
                        );
                        final source = SourceView(
                          lines: report.script.displayLines,
                          findings: report.findings,
                          selectedLine: _selectedLine,
                          onLineTap: (l) => setState(() => _selectedLine = l),
                        );
                        // Code et résultats séparés par une barre déplaçable ;
                        // répartition mémorisée par disposition.
                        final wide = c.maxWidth > 1000;
                        final g = state.settings;
                        return SplitView(
                          key: ValueKey(wide),
                          axis: wide ? Axis.horizontal : Axis.vertical,
                          first: source,
                          second: side,
                          state: wide ? g.wideSplit : g.narrowSplit,
                          defaultState: wide
                              ? GuiSettings.defaultWideSplit
                              : GuiSettings.defaultNarrowSplit,
                          minFirst: wide ? 240 : 120,
                          minSecond: wide ? 360 : 200,
                          collapseFirstTooltip: s.hideSource,
                          collapseSecondTooltip: s.hideResults,
                          restoreTooltip: s.showBoth,
                          onChanged: (v) => state.updateSettings(wide
                              ? g.copyWith(wideSplit: v)
                              : g.copyWith(narrowSplit: v)),
                        );
                      }),
              ),
            ]));
  }

  /// Signale un faux positif : aperçu anonymisé, commentaire, puis
  /// proposition de ne plus signaler la règle.
  Future<void> _falsePositive(
      BuildContext context, ScriptReport report, Finding f) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final preview = FalsePositive.of(f, report);
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.reportFalsePositive} — ${f.ruleId}'),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.falsePositiveIntro),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              child: SelectableText(
                  [
                    for (var i = 0; i < preview.context.length; i++)
                      '${i == preview.focus ? '▶' : ' '} '
                          '${preview.context[i] ?? '…'}'
                  ].join('\n'),
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: comment,
              maxLines: 2,
              decoration: InputDecoration(
                  labelText: s.falsePositiveComment,
                  border: const OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.save)),
        ],
      ),
    );
    final text = comment.text;
    comment.dispose();
    if (ok != true) return;
    final n = await state.reportFalsePositive(f, comment: text);
    if (n == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text(s.falsePositiveSaved(n)),
      action: SnackBarAction(
          label: s.doNotReport(f.ruleId),
          onPressed: () => state.setRuleEnabled(f.ruleId, false)),
    ));
  }

  /// Ouvre le script dans l'éditeur, à la ligne [line].
  Future<void> _edit(BuildContext context, String path, int line) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final err = await openInEditor(state.settings.editorCommand, path, line);
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text(s.error(err))));
    }
  }

  /// Corrige toutes les occurrences de la règle d'un problème.
  Future<void> _applyRule(BuildContext context, Finding f) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final n = state.fixableOfRule(f).length;
    final why = await state.applyRuleFixes(f);
    messenger.showSnackBar(SnackBar(
        content: Text(switch (why) {
      null => s.rulesFixed(n, f.ruleId),
      AppState.staleFix => s.fixStale,
      _ => s.fixAborted(why),
    })));
  }

  /// Désactive la règle d'un problème (effet à la prochaine analyse).
  Future<void> _disableRule(BuildContext context, Finding f) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    await state.setRuleEnabled(f.ruleId, false);
    messenger.showSnackBar(SnackBar(
      content: Text(s.ruleDisabled(f.ruleId)),
      action: SnackBarAction(
          label: s.reanalyze,
          onPressed: () {
            if (!state.busy) state.reanalyze();
          }),
    ));
  }

  /// Applique la correction d'un seul problème, depuis la liste.
  /// Corrections cochées : diff global, puis application en une fois.
  Future<void> _applySelection(
      BuildContext context, List<Finding> findings) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final preview = await state.previewFixes(findings);
    if (!context.mounted) return;
    if (preview == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.fixStale)));
      return;
    }
    final (before, after) = preview;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.selectionTitle(findings.length)),
        content: SizedBox(
          width: 760,
          height: 480,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(findings.map((f) => '${f.ruleId} L${f.line}').join(', ')),
            Text(s.backupHint, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(child: DiffView(diff: unifiedDiff(before, after))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.apply)),
        ],
      ),
    );
    if (ok != true) return;
    final why = await state.applySelectedFixes(findings);
    messenger.showSnackBar(SnackBar(
        content: Text(switch (why) {
      null => s.selectionApplied(findings.length),
      AppState.staleFix => s.fixStale,
      _ => s.fixAborted(why),
    })));
  }

  Future<void> _applyOne(BuildContext context, Finding f) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final why = await state.applyFindingFix(f);
    messenger.showSnackBar(SnackBar(
        content: Text(switch (why) {
      null => s.singleFixApplied(f.ruleId),
      AppState.staleFix => s.fixStale,
      _ => s.fixAborted(why),
    })));
  }

  Future<void> _fix(BuildContext context) async {
    final s = S(state.lang);
    final messenger = ScaffoldMessenger.of(context);
    final r = await state.proposeFix();
    if (r == null || !context.mounted) return;
    if (r.aborted != null) {
      messenger.showSnackBar(SnackBar(content: Text(s.fixAborted(r.aborted!))));
      return;
    }
    if (!r.changed) {
      messenger.showSnackBar(SnackBar(content: Text(s.noFix)));
      return;
    }
    final summary =
        r.applied.entries.map((e) => '${e.key} ×${e.value}').join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.fixTitle),
        content: SizedBox(
          width: 760,
          height: 480,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(summary),
            Text(s.backupHint, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(child: DiffView(diff: unifiedDiff(r.original, r.fixed))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.apply)),
        ],
      ),
    );
    if (ok == true) {
      await state.applyFix(r);
      messenger.showSnackBar(SnackBar(content: Text(s.fixApplied(summary))));
    }
  }
}

/// Affichage coloré d'un diff unifié.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.diff});
  final String diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = diff.split('\n');
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListView.builder(
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final l = lines[i];
          Color? bg;
          if (l.startsWith('+') && !l.startsWith('+++')) {
            bg = Colors.green.withValues(alpha: 0.18);
          } else if (l.startsWith('-') && !l.startsWith('---')) {
            bg = Colors.red.withValues(alpha: 0.18);
          } else if (l.startsWith('@@')) {
            bg = theme.colorScheme.primary.withValues(alpha: 0.12);
          }
          return Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(l,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                softWrap: false),
          );
        },
      ),
    );
  }
}

/// Bouton de chargement / retrait de la référence.
class BaselineButton extends StatelessWidget {
  const BaselineButton({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    if (state.baseline != null) {
      return InputChip(
        avatar: const Icon(Icons.compare_arrows, size: 18),
        label: Text(
            '${s.baselineLoaded} : ${state.baselinePath!.split('/').last}'),
        onDeleted: state.busy ? null : state.clearBaseline,
        deleteButtonTooltipMessage: s.clearBaseline,
      );
    }
    return OutlinedButton.icon(
      onPressed: state.busy
          ? null
          : () async {
              final r = await FilePicker.pickFiles(
                  dialogTitle: s.loadBaseline,
                  type: FileType.custom,
                  allowedExtensions: ['json']);
              final path = r?.files.single.path;
              if (path != null) await state.loadBaseline(path);
            },
      icon: const Icon(Icons.compare_arrows),
      label: Text(s.loadBaseline),
    );
  }
}

/// Exporte des rapports vers un fichier choisi (format selon l'extension).
Future<void> exportReports(
    BuildContext context, AppState state, List<ScriptReport> reports) async {
  final s = S(state.lang);
  final messenger = ScaffoldMessenger.of(context);
  final base = reports.length == 1
      ? reports.single.script.path
          .split('/')
          .last
          .replaceAll(RegExp(r'\.\w+$'), '')
      : 'check-script';
  final path = await FilePicker.saveFile(
    dialogTitle: s.export,
    fileName: '$base-report.html',
    type: FileType.custom,
    allowedExtensions: ['html', 'md', 'adoc', 'json', 'sarif', 'txt'],
  );
  if (path == null) return;
  try {
    await state.export(path, reports);
    messenger.showSnackBar(SnackBar(content: Text(s.exported(path))));
  } on FileSystemException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.error(e.message))));
  }
}
