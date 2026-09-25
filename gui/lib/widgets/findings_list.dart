/// Liste des problèmes avec filtres par catégorie et sévérité ; un clic
/// sélectionne la ligne dans le source et déplie le code à écrire pour
/// résoudre le problème ; le lien ouvre la documentation.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../strings.dart';
import 'common.dart';
import 'fix_panel.dart';

class FindingsList extends StatefulWidget {
  const FindingsList({
    super.key,
    required this.findings,
    required this.lang,
    this.lines = const [],
    this.onSelect,
    this.onApplyFix,
    this.onDisableRule,
    this.onApplyRule,
    this.explanation,
    this.onOpenInEditor,
    this.onReportFalsePositive,
  });

  final List<Finding> findings;
  final Lang lang;

  /// Lignes du script (aperçu des corrections concrètes).
  final List<String> lines;
  final void Function(Finding f)? onSelect;

  /// Applique la correction concrète d'un problème ; null : pas de bouton.
  final void Function(Finding f)? onApplyFix;

  /// Désactive la règle d'un problème ; null : pas de bouton.
  final void Function(Finding f)? onDisableRule;

  /// Corrige toutes les occurrences de la règle d'un problème ; null : pas
  /// de bouton.
  final void Function(Finding f)? onApplyRule;

  /// Explication de la note : permet le tri par gain rapide.
  final ScoreExplanation? explanation;

  /// Ouvre le script dans l'éditeur à la ligne du problème ; null : pas de
  /// bouton.
  final void Function(Finding f)? onOpenInEditor;

  /// Signale un problème comme faux positif ; null : pas de bouton.
  final void Function(Finding f)? onReportFalsePositive;

  @override
  State<FindingsList> createState() => _FindingsListState();
}

class _FindingsListState extends State<FindingsList> {
  final _categories = Category.values.toSet();
  final _severities = Severity.values.toSet();

  /// Problème déplié (code de correction affiché).
  Finding? _open;

  /// Tri par gain rapide plutôt que par catégorie.
  bool _quickWin = false;

  @override
  void didUpdateWidget(FindingsList old) {
    super.didUpdateWidget(old);
    if (!identical(old.findings, widget.findings)) _open = null;
  }

  /// Filtre pur, exposé pour les tests.
  static List<Finding> filter(
          List<Finding> all, Set<Category> cats, Set<Severity> sevs) =>
      [
        for (final f in all)
          if (cats.contains(f.category) && sevs.contains(f.severity)) f
      ];

  @override
  Widget build(BuildContext context) {
    final s = S(widget.lang);
    final t = s.m;
    final b = Theme.of(context).brightness;
    final filtered = filter(widget.findings, _categories, _severities);
    final e = widget.explanation;
    final shown =
        _quickWin && e != null ? sortByQuickWin(filtered, e) : filtered;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final c in Category.values)
          FilterChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(
                '${t.category(c)} (${widget.findings.where((f) => f.category == c).length})'),
            selected: _categories.contains(c),
            onSelected: (v) =>
                setState(() => v ? _categories.add(c) : _categories.remove(c)),
          ),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 6, children: [
        for (final sev in Severity.values)
          FilterChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(sev.label,
                style: TextStyle(
                    color: severityColor(sev, b), fontWeight: FontWeight.w600)),
            selected: _severities.contains(sev),
            onSelected: (v) => setState(
                () => v ? _severities.add(sev) : _severities.remove(sev)),
          ),
      ]),
      if (widget.explanation != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, label: Text(s.sortCategory)),
              ButtonSegment(value: true, label: Text(s.sortQuickWin)),
            ],
            selected: {_quickWin},
            onSelectionChanged: (v) => setState(() => _quickWin = v.first),
          ),
        ),
      const Divider(),
      Expanded(
        child: shown.isEmpty
            ? Center(child: Text(t.noIssue))
            : ListView.separated(
                itemCount: shown.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final f = shown[i];
                  final open = identical(f, _open);
                  return ListTile(
                    dense: true,
                    selected: open,
                    onTap: () {
                      setState(() => _open = open ? null : f);
                      widget.onSelect?.call(f);
                    },
                    // ListTile limite la hauteur de leading (48 px) : badge
                    // et ligne sont réduits plutôt que de déborder (libellé
                    // « fichier entier » sur deux lignes).
                    leading: SizedBox(
                      width: 64,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          SeverityBadge(f.severity),
                          const SizedBox(height: 2),
                          Text(f.line == 0 ? s.wholeFile : 'L${f.line}',
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelSmall),
                        ]),
                      ),
                    ),
                    title: Text(f.message),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${f.ruleId} · ${f.tool} · ${t.category(f.category)}',
                              style: Theme.of(context).textTheme.labelSmall),
                          if (f.hint != null) Text('→ ${f.hint}'),
                          if (open)
                            FixPanel(
                              finding: f,
                              lines: widget.lines,
                              lang: widget.lang,
                              onApply: widget.onApplyFix == null
                                  ? null
                                  : () => widget.onApplyFix!(f),
                              ruleOccurrences: widget.findings
                                  .where((x) =>
                                      x.ruleId == f.ruleId &&
                                      x.edits.isNotEmpty)
                                  .length,
                              onApplyRule: widget.onApplyRule == null
                                  ? null
                                  : () => widget.onApplyRule!(f),
                            ),
                          if (open &&
                              widget.onOpenInEditor != null &&
                              f.line > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.edit_note, size: 18),
                                label: Text(s.openAtLine(f.line)),
                                onPressed: () => widget.onOpenInEditor!(f),
                              ),
                            ),
                          if (open && widget.onReportFalsePositive != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.flag_outlined, size: 18),
                                label: Text(s.reportFalsePositive),
                                onPressed: () =>
                                    widget.onReportFalsePositive!(f),
                              ),
                            ),
                          if (open && widget.onDisableRule != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon:
                                    const Icon(Icons.visibility_off, size: 16),
                                label: Text(s.doNotReport(f.ruleId)),
                                onPressed: () => widget.onDisableRule!(f),
                              ),
                            ),
                        ]),
                    trailing: f.url == null
                        ? null
                        : IconButton(
                            tooltip: s.documentation,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            onPressed: () => launchUrl(Uri.parse(f.url!)),
                          ),
                  );
                },
              ),
      ),
    ]);
  }
}
