/// Écran d'analyse d'un script : source annotée à gauche, notes et problèmes
/// à droite ; actions ouvrir, relancer, corriger, exporter, référence.
library;

import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../code_style.dart';
import '../editor.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';
import '../help/tips.dart';
import '../strings.dart';
import '../widgets/findings_list.dart';
import '../widgets/score_panel.dart';
import '../widgets/source_view.dart';
import '../widgets/split_view.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.state, this.findRequest});
  final AppState state;

  /// Demande de recherche (Ctrl+F) : ouvre la recherche dans le code, ou met
  /// le focus sur la recherche des problèmes si cet onglet est affiché.
  final ValueListenable<int>? findRequest;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  int? _selectedLine;

  /// Onglets Synthèse / Problèmes (le premier est affiché au départ).
  late final _tabs = TabController(length: 2, vsync: this);

  /// Recherche dans le code : champ ouvert, texte, occurrence courante.
  bool _searching = false;
  final _codeQuery = TextEditingController();
  final _codeFocus = FocusNode();
  int _matchIndex = 0;

  /// Demande de focus sur la recherche de la liste des problèmes.
  final _issuesFind = ValueNotifier<int>(0);

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    widget.findRequest?.addListener(_onFind);
  }

  @override
  void didUpdateWidget(AnalysisScreen old) {
    super.didUpdateWidget(old);
    if (old.findRequest != widget.findRequest) {
      old.findRequest?.removeListener(_onFind);
      widget.findRequest?.addListener(_onFind);
    }
  }

  @override
  void dispose() {
    widget.findRequest?.removeListener(_onFind);
    _tabs.dispose();
    _codeQuery.dispose();
    _codeFocus.dispose();
    _issuesFind.dispose();
    super.dispose();
  }

  void _onFind() {
    if (state.current == null) return;
    if (_tabs.index == 1) {
      _issuesFind.value++;
    } else {
      _openSearch();
    }
  }

  /// Ouvre la recherche dans le code et lui donne le focus.
  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeFocus.requestFocus();
      _codeQuery.selection =
          TextSelection(baseOffset: 0, extentOffset: _codeQuery.text.length);
    });
  }

  /// Numéros des lignes du code contenant le texte cherché.
  List<int> _matches(ScriptReport report) {
    final q = _codeQuery.text.trim().toLowerCase();
    if (!_searching || q.isEmpty) return const [];
    final lines = report.script.displayLines;
    return [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].toLowerCase().contains(q)) i + 1
    ];
  }

  /// Va à l'occurrence suivante ([step] 1) ou précédente (-1), en boucle.
  void _gotoMatch(ScriptReport report, int step) {
    final m = _matches(report);
    if (m.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex + step) % m.length;
      _selectedLine = m[_matchIndex];
    });
  }

  void _closeSearch() => setState(() {
        _searching = false;
        _codeQuery.clear();
        _matchIndex = 0;
      });

  Future<void> _open() async {
    final r = await FilePicker.pickFiles(
        dialogTitle: S(state.lang).openScript, allowMultiple: true);
    for (final f in r?.files ?? const <PlatformFile>[]) {
      final path = f.path;
      if (path != null) await state.analyzeFile(path);
    }
  }

  /// Taille du code : +/- [delta] points, null : taille par défaut.
  void _zoom(double? delta) =>
      state.updateSettings(state.settings.zoomCode(delta));

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final report = state.current;
    return _body(context, s, report, Tips(state.lang));
  }

  Widget _body(BuildContext context, S s, ScriptReport? report, Tips tp) {
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
                          tip(
                              tp.openScript,
                              FilledButton.icon(
                                  onPressed: state.busy ? null : _open,
                                  icon: const Icon(Icons.file_open),
                                  label: Text(s.openScript))),
                          tip(
                              tp.reanalyze,
                              OutlinedButton.icon(
                                  onPressed: state.busy || report == null
                                      ? null
                                      : state.reanalyze,
                                  icon: const Icon(Icons.refresh),
                                  label: Text(s.reanalyze))),
                          tip(
                              tp.fix,
                              OutlinedButton.icon(
                                  onPressed: state.busy || report == null
                                      ? null
                                      : () => _fix(context),
                                  icon: const Icon(Icons.auto_fix_high),
                                  label: Text(s.fix))),
                          tip(
                              tp.export,
                              OutlinedButton.icon(
                                  onPressed: report == null
                                      ? null
                                      : () => exportReports(
                                          context, state, [report]),
                                  icon: const Icon(Icons.save_alt),
                                  label: Text(s.export))),
                          tip(
                              tp.openInEditor,
                              OutlinedButton.icon(
                                  onPressed: report == null ||
                                          report.script.path == '<stdin>'
                                      ? null
                                      : () => _edit(context, report.script.path,
                                          _selectedLine ?? 1),
                                  icon: const Icon(Icons.edit_note),
                                  label: Text(s.openInEditor))),
                          ...baselineActions(context, state,
                              hasReport: report != null),
                          HelpButton(HelpTopic.analysis, lang: state.lang),
                          if (report != null)
                            Text(report.script.path,
                                style: Theme.of(context).textTheme.bodySmall),
                        ]),
                  ),
                ),
              ),
              if (state.openTabs.length >= 2)
                _DocTabs(state: state, tips: tp, closeLabel: s.closeTab),
              const Divider(height: 1),
              Expanded(
                child: report == null
                    ? Center(
                        child: Text(s.dropHere, textAlign: TextAlign.center))
                    : LayoutBuilder(builder: (context, c) {
                        final issues = detailFindings(report);
                        final side = Column(children: [
                          TabBar(controller: _tabs, tabs: [
                            tip(tp.tabSummary, Tab(text: s.summary)),
                            tip(tp.tabIssues,
                                Tab(text: '${s.issues} (${issues.length})')),
                          ]),
                          Expanded(
                            child: TabBarView(controller: _tabs, children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                child: ScorePanel(
                                    report: report, lang: state.lang),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: FindingsList(
                                  findings: issues,
                                  findRequest: _issuesFind,
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
                                  onReportFalsePositive: state.falsePositives ==
                                          null
                                      ? null
                                      : (f) =>
                                          _falsePositive(context, report, f),
                                ),
                              ),
                            ]),
                          ),
                        ]);
                        final g0 = state.settings;
                        final source = SourceView(
                          lines: report.script.displayLines,
                          findings: report.findings,
                          selectedLine: _selectedLine,
                          onLineTap: (l) => setState(() => _selectedLine = l),
                          language: HighlightLanguage.of(report.script),
                          fontFamily: g0.codeFont,
                          fontSize: g0.codeFontSize,
                          onZoom: _zoom,
                          matchLines: _matches(report).toSet(),
                          header: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ZoomBar(
                                    state: state,
                                    onZoom: _zoom,
                                    searching: _searching,
                                    onSearch: _searching
                                        ? _closeSearch
                                        : _openSearch),
                                if (_searching)
                                  _CodeSearchBar(
                                    controller: _codeQuery,
                                    focus: _codeFocus,
                                    lang: state.lang,
                                    count: _matches(report).length,
                                    index: _matchIndex,
                                    onChanged: () => setState(() {
                                      _matchIndex = 0;
                                      final m = _matches(report);
                                      if (m.isNotEmpty) _selectedLine = m.first;
                                    }),
                                    onStep: (d) => _gotoMatch(report, d),
                                    onClose: _closeSearch,
                                  ),
                              ]),
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
                  style: CodeFont.styleOf(ctx)),
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

/// Taille du texte du code : A− / taille / A+ ; clic sur la taille :
/// taille par défaut.
class _ZoomBar extends StatelessWidget {
  const _ZoomBar({
    required this.state,
    required this.onZoom,
    required this.searching,
    required this.onSearch,
  });
  final AppState state;
  final void Function(double? delta) onZoom;

  /// Recherche dans le code ouverte ; [onSearch] l'ouvre ou la ferme.
  final bool searching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final g = state.settings;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Row(children: [
        const SizedBox(width: 8),
        Flexible(
          child: tip(
              Tips(state.lang).codeFont,
              Text(g.codeFont ?? defaultCodeFont,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall)),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: Tips(state.lang).searchCode,
          isSelected: searching,
          onPressed: onSearch,
          icon: const Icon(Icons.search, size: 18),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '${s.smallerText} (Ctrl+−)',
          onPressed:
              g.codeFontSize <= minCodeFontSize ? null : () => onZoom(-1),
          icon: const Icon(Icons.text_decrease, size: 18),
        ),
        Tooltip(
          message: '${s.defaultTextSize} (Ctrl+0)',
          child: TextButton(
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(48, 32)),
            onPressed: () => onZoom(null),
            child: Text('${g.codeFontSize.round()} pt'),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '${s.largerText} (Ctrl+plus)',
          onPressed: g.codeFontSize >= maxCodeFontSize ? null : () => onZoom(1),
          icon: const Icon(Icons.text_increase, size: 18),
        ),
      ]),
    );
  }
}

/// Barre de recherche dans le code : champ, nombre d'occurrences,
/// précédente / suivante, fermeture. Entrée : suivante ; Maj+Entrée :
/// précédente ; Échap : ferme.
class _CodeSearchBar extends StatelessWidget {
  const _CodeSearchBar({
    required this.controller,
    required this.focus,
    required this.lang,
    required this.count,
    required this.index,
    required this.onChanged,
    required this.onStep,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final Lang lang;
  final int count;
  final int index;
  final VoidCallback onChanged;
  final void Function(int step) onStep;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = S(lang);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
              onStep(-1),
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                autofocus: true,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: s.searchCode,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) {
                  onStep(1);
                  focus.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            if (controller.text.trim().isNotEmpty)
              Text(s.matchCount(index, count),
                  style: theme.textTheme.labelSmall),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: s.previousMatch,
              onPressed: count == 0 ? null : () => onStep(-1),
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: s.nextMatch,
              onPressed: count == 0 ? null : () => onStep(1),
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: s.closeSearch,
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Onglets des scripts ouverts : un clic affiche le script, la croix le
/// ferme.
class _DocTabs extends StatelessWidget {
  const _DocTabs(
      {required this.state, required this.tips, required this.closeLabel});
  final AppState state;
  final Tips tips;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final path in state.openTabs)
              _DocTab(
                path: path,
                active: path == state.activeTab,
                tooltip: '$path\n${tips.tab}',
                closeLabel: closeLabel,
                onTap: () => state.selectTab(path),
                onClose: () => state.closeTab(path),
              ),
          ],
        ),
      ),
    );
  }
}

class _DocTab extends StatelessWidget {
  const _DocTab({
    required this.path,
    required this.active,
    required this.tooltip,
    required this.closeLabel,
    required this.onTap,
    required this.onClose,
  });
  final String path;
  final bool active;
  final String tooltip;
  final String closeLabel;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = active
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 12, right: 2),
          decoration: BoxDecoration(
            color: active ? theme.colorScheme.secondaryContainer : null,
            border: Border(
                bottom: BorderSide(
                    width: 2,
                    color: active
                        ? theme.colorScheme.primary
                        : Colors.transparent)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(path.split('/').last,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: closeLabel,
              onPressed: onClose,
              icon: Icon(Icons.close, color: fg),
            ),
          ]),
        ),
      ),
    );
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
            child: Text(l, style: CodeFont.styleOf(context), softWrap: false),
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
      return tip(
        Tips(state.lang).baselineChip,
        InputChip(
          avatar: const Icon(Icons.compare_arrows, size: 18),
          label: Text(
              '${s.baselineLoaded} : ${state.baselinePath!.split('/').last}'),
          onDeleted: state.busy ? null : state.clearBaseline,
          deleteButtonTooltipMessage: s.clearBaseline,
        ),
      );
    }
    return tip(
        Tips(state.lang).loadBaseline,
        OutlinedButton.icon(
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
        ));
  }
}

/// Boutons de la référence : charger ou retirer, et « Définir comme
/// référence » (enregistre l'analyse affichée en JSON puis la charge).
/// [folder] : l'analyse du dossier plutôt que du script.
List<Widget> baselineActions(BuildContext context, AppState state,
    {required bool hasReport, bool folder = false}) {
  final s = S(state.lang);
  return [
    BaselineButton(state: state),
    if (state.baseline == null)
      tip(
        Tips(state.lang).setBaseline,
        OutlinedButton.icon(
          onPressed: state.busy || !hasReport
              ? null
              : () => _setBaseline(context, state, folder: folder),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(s.setBaseline),
        ),
      ),
  ];
}

Future<void> _setBaseline(BuildContext context, AppState state,
    {required bool folder}) async {
  final s = S(state.lang);
  final messenger = ScaffoldMessenger.of(context);
  final base = folder
      ? 'baseline'
      : (state.current?.script.path.split('/').last ?? 'script')
          .replaceAll(RegExp(r'\.\w+$'), '');
  final path = await FilePicker.saveFile(
    dialogTitle: s.setBaseline,
    fileName: '$base-baseline.json',
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (path == null) return;
  try {
    final written = await state.setAsBaseline(path, folder: folder);
    if (written != null) {
      messenger.showSnackBar(SnackBar(content: Text(s.baselineSet(written))));
    }
  } on FileSystemException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.error(e.message))));
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
    allowedExtensions: ['html', 'pdf', 'md', 'adoc', 'json', 'sarif', 'txt'],
  );
  if (path == null) return;
  try {
    await state.export(path, reports);
    messenger.showSnackBar(SnackBar(content: Text(s.exported(path))));
  } on FileSystemException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.error(e.message))));
  }
}
