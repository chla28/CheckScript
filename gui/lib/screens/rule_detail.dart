/// Détail d'une règle : description, catégorie, sévérité, références,
/// exemple « à éviter / à écrire », équivalents dans d'autres outils,
/// occurrences dans les analyses affichées, activation, façons de l'ignorer.
/// Mêmes informations que `check-script explain`.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../code_style.dart';
import '../help/tips.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../widgets/fix_panel.dart' show CodeBlock;

/// Occurrences de la règle [key] dans l'analyse du script affiché : lignes.
List<int> ruleLinesInCurrent(AppState state, String key) => [
      for (final f in state.current?.findings ?? const <Finding>[])
        if (f.ruleId.toUpperCase() == key) f.line
    ];

/// Occurrences de la règle [key] dans l'analyse du dossier : (total, nombre
/// de scripts concernés).
(int, int) ruleCountInFolder(AppState state, String key) {
  var total = 0, scripts = 0;
  for (final r in state.folderReports) {
    final n = r.findings.where((f) => f.ruleId.toUpperCase() == key).length;
    total += n;
    if (n > 0) scripts++;
  }
  return (total, scripts);
}

/// Ouvre le détail de la règle [e]. [locked] : désactivée par le profil ou
/// le fichier YAML (non modifiable ici).
Future<void> showRuleDetail(BuildContext context, AppState state, RuleEntry e,
    {required bool locked}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: state,
      builder: (ctx, _) => _RuleDetail(state: state, entry: e, locked: locked),
    ),
  );
}

class _RuleDetail extends StatelessWidget {
  const _RuleDetail(
      {required this.state, required this.entry, required this.locked});
  final AppState state;
  final RuleEntry entry;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final s = S(state.lang);
    final t = s.m;
    final tp = Tips(state.lang);
    final theme = Theme.of(context);
    final e = entry;
    final enabled = !locked && !state.settings.disabledRules.contains(e.key);
    final example = exampleFor(e.id);
    final same = sameRuleIds(e.id).toList()..sort();
    final here = ruleLinesInCurrent(state, e.key);
    final (inFolder, inScripts) = ruleCountInFolder(state, e.key);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(text, style: theme.textTheme.titleSmall),
        );

    Widget copyLine(String text) => Row(children: [
          Expanded(
              child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest,
            child: SelectableText(text, style: CodeFont.styleOf(context)),
          )),
          IconButton(
            tooltip: s.copy,
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              await Clipboard.setData(ClipboardData(text: text));
              messenger?.showSnackBar(SnackBar(content: Text(s.copied)));
            },
          ),
        ]);

    return AlertDialog(
      title: Text.rich(TextSpan(children: [
        TextSpan(
            text: e.id,
            style: const TextStyle(
                fontFamily: 'monospace', fontWeight: FontWeight.w700)),
        if (e.title.isNotEmpty) TextSpan(text: '  ${e.title}'),
      ])),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(spacing: 8, runSpacing: 4, children: [
                  Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(t.category(e.category))),
                  e.severity == null
                      ? Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(s.severityVaries))
                      : SeverityBadge(e.severity!),
                  Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${t.tool}: ${e.tool}')),
                  if (e.language != ToolLanguage.any)
                    Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(e.language.name)),
                ]),
                if (e.refs.isNotEmpty) ...[
                  label(s.references),
                  SelectableText(e.refs.join(' · ')),
                ],
                if (e.url != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(s.documentation),
                      onPressed: () => launchUrl(Uri.parse(e.url!)),
                    ),
                  ),
                label(s.ruleExample),
                if (example == null)
                  Text(s.noRuleExample, style: theme.textTheme.bodySmall)
                else ...[
                  Text(t.avoid, style: theme.textTheme.labelSmall),
                  CodeBlock(example.badOf(state.lang), good: false),
                  const SizedBox(height: 6),
                  Text(t.writeInstead, style: theme.textTheme.labelSmall),
                  CodeBlock(example.goodOf(state.lang), good: true),
                ],
                if (same.isNotEmpty) ...[
                  label(s.ruleEquivalents),
                  SelectableText(same.join(', ')),
                ],
                label(s.ruleOccurrences),
                Text(here.isEmpty
                    ? s.noOccurrenceHere
                    : s.occurrencesHere(here.length, here)),
                if (state.folderReports.isNotEmpty)
                  Text(s.occurrencesInFolder(inFolder, inScripts)),
                const SizedBox(height: 8),
                tip(
                  locked ? tp.lockedRule : tp.ruleCheckbox,
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(s.ruleReported),
                    subtitle: Text(locked ? s.lockedByConfig : s.nextScanHint),
                    value: enabled,
                    onChanged:
                        locked ? null : (v) => state.setRuleEnabled(e.key, v),
                  ),
                ),
                label(s.ruleIgnoreHow),
                copyLine('# check-script disable=${e.id}'),
                copyLine('check-script explain ${e.id}'),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.close)),
      ],
    );
  }
}
