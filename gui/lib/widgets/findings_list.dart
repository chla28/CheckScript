/// Liste des problèmes avec filtres par catégorie et sévérité ; un clic
/// sélectionne la ligne dans le source, le lien ouvre la documentation.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../strings.dart';
import 'common.dart';

class FindingsList extends StatefulWidget {
  const FindingsList({
    super.key,
    required this.findings,
    required this.lang,
    this.onSelect,
  });

  final List<Finding> findings;
  final Lang lang;
  final void Function(Finding f)? onSelect;

  @override
  State<FindingsList> createState() => _FindingsListState();
}

class _FindingsListState extends State<FindingsList> {
  final _categories = Category.values.toSet();
  final _severities = Severity.values.toSet();

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
                  return ListTile(
                    dense: true,
                    onTap: widget.onSelect == null
                        ? null
                        : () => widget.onSelect!(f),
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
