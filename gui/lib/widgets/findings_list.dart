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
  });

  final List<Finding> findings;
  final Lang lang;

  /// Lignes du script (aperçu des corrections concrètes).
  final List<String> lines;
  final void Function(Finding f)? onSelect;

  /// Applique la correction concrète d'un problème ; null : pas de bouton.
  final void Function(Finding f)? onApplyFix;

  @override
  State<FindingsList> createState() => _FindingsListState();
}

class _FindingsListState extends State<FindingsList> {
  final _categories = Category.values.toSet();
  final _severities = Severity.values.toSet();

  /// Problème déplié (code de correction affiché).
  Finding? _open;

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
    final shown = filter(widget.findings, _categories, _severities);

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
                    leading: SizedBox(
                      width: 64,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SeverityBadge(f.severity),
                            const SizedBox(height: 2),
                            Text(f.line == 0 ? s.wholeFile : 'L${f.line}',
                                style: Theme.of(context).textTheme.labelSmall),
                          ]),
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
