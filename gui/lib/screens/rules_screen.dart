/// Règles de détection : toutes les règles connues (intégrées, codes classés
/// des outils, codes rencontrés lors des analyses), chacune avec une case à
/// cocher ; une règle décochée n'est plus signalée à partir de l'analyse
/// suivante. Recherche, filtres, saisie libre d'un code.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';
import '../help/tips.dart';
import '../strings.dart';
import '../widgets/common.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, required this.state, this.findRequest});
  final AppState state;

  /// Demande de recherche (Ctrl+F) : met le focus sur le champ de recherche.
  final ValueListenable<int>? findRequest;

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _add = TextEditingController();
  ToolLanguage? _language;
  String? _tool;
  Category? _category;

  /// Règles désactivées par le profil ou le fichier YAML (non modifiables
  /// ici), et réglages pour lesquels elles ont été calculées.
  Set<String> _locked = const {};
  (Profile, String?)? _lockedFor;

  /// Règles personnalisées de la configuration (rules.custom).
  List<CustomRule> _custom = const [];

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    widget.findRequest?.addListener(_focusSearch);
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection =
        TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  @override
  void dispose() {
    widget.findRequest?.removeListener(_focusSearch);
    _search.dispose();
    _searchFocus.dispose();
    _add.dispose();
    super.dispose();
  }

  void _refreshLocked() {
    final g = state.settings;
    final key = (g.profile, g.configPath);
    if (_lockedFor == key) return;
    _lockedFor = key;
    state.baseConfig().then((c) {
      if (mounted) {
        setState(() {
          _locked = c.disabledRules;
          _custom = c.customRules;
        });
      }
    }, onError: (_) {});
  }

  /// Règles connues, puis rencontrées, puis saisies (désactivées mais
  /// inconnues du registre).
  static List<RuleEntry> allEntries(AppState state, Lang lang, String typed,
      {List<CustomRule> custom = const []}) {
    final known = [...knownRules(lang), ...customRuleEntries(custom, lang)];
    final keys = {for (final e in known) e.key};
    final out = [...known];
    for (final e in state.seenRules.values) {
      if (keys.add(e.key)) out.add(e);
    }
    for (final k in state.settings.disabledRules) {
      if (keys.add(k)) {
        out.add(RuleEntry(
            id: k,
            tool: '—',
            language: ToolLanguage.any,
            category: Category.robustness,
            title: typed));
      }
    }
    return out;
  }

  bool _matches(RuleEntry e) {
    if (_language != null &&
        e.language != _language &&
        e.language != ToolLanguage.any) {
      return false;
    }
    if (_tool != null && !e.tool.split(', ').contains(_tool)) return false;
    if (_category != null && e.category != _category) return false;
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty ||
        e.id.toLowerCase().contains(q) ||
        e.title.toLowerCase().contains(q) ||
        e.tool.toLowerCase().contains(q) ||
        e.refs.any((r) => r.toLowerCase().contains(q));
  }

  void _addTyped() {
    final code = _add.text.trim();
    if (code.isEmpty) return;
    state.setRuleEnabled(code, false);
    _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    _refreshLocked();
    final s = S(state.lang);
    final t = s.m;
    final tp = Tips(state.lang);
    final g = state.settings;
    final theme = Theme.of(context);
    final entries = allEntries(state, state.lang, s.typedCode, custom: _custom);
    final shown = entries.where(_matches).toList();
    final disabled = entries
        .where(
            (e) => g.disabledRules.contains(e.key) || _locked.contains(e.key))
        .length;
    final tools = {
      for (final e in entries)
        for (final tool in e.tool.split(', '))
          if (tool != '—') tool
    }.toList()
      ..sort();

    Widget dropdown<T>(T? value, String all, Map<T, String> items,
            ValueChanged<T?> onChanged, String help) =>
        tip(
          help,
          DropdownButton<T?>(
            value: value,
            isDense: true,
            items: [
              DropdownMenuItem(value: null, child: Text(all)),
              for (final e in items.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: onChanged,
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: tip(
                tp.searchRules,
                TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: s.searchRules,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            dropdown<ToolLanguage>(
                _language,
                s.allLanguages,
                {
                  ToolLanguage.shell: 'shell',
                  ToolLanguage.python: 'python',
                },
                (v) => setState(() => _language = v),
                tp.languageFilter),
            dropdown<String>(_tool, s.allTools, {for (final x in tools) x: x},
                (v) => setState(() => _tool = v), tp.toolFilter),
            dropdown<Category>(
                _category,
                s.allCategories,
                {for (final c in Category.values) c: t.category(c)},
                (v) => setState(() => _category = v),
                tp.categoryFilter),
            HelpButton(HelpTopic.rules, lang: state.lang),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(s.rulesCount(shown.length, entries.length, disabled),
                style: theme.textTheme.bodyMedium),
            tip(
              tp.enableAll,
              OutlinedButton.icon(
                onPressed:
                    g.disabledRules.isEmpty ? null : state.enableAllRules,
                icon: const Icon(Icons.done_all),
                label: Text(s.enableAll(g.disabledRules.length)),
              ),
            ),
            tip(
              tp.reanalyze,
              FilledButton.tonalIcon(
                onPressed: state.busy || state.current == null
                    ? null
                    : state.reanalyze,
                icon: const Icon(Icons.refresh),
                label: Text(s.reanalyze),
              ),
            ),
            Text(s.nextScanHint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          SizedBox(
            width: 320,
            child: tip(
              tp.disableOther,
              TextField(
                controller: _add,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: s.disableOtherHint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addTyped(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          tip(
            tp.disableOther,
            OutlinedButton.icon(
              onPressed: _addTyped,
              icon: const Icon(Icons.block),
              label: Text(s.disableOther),
            ),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final e = shown[i];
            final locked = _locked.contains(e.key);
            final enabled = !locked && !g.disabledRules.contains(e.key);
            final sev = e.severity;
            return tip(
                locked ? tp.lockedRule : tp.ruleCheckbox,
                CheckboxListTile(
                  key: ValueKey(e.key),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: enabled,
                  onChanged: locked
                      ? null
                      : (v) => state.setRuleEnabled(e.key, v ?? true),
                  title: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: e.id,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600)),
                    if (e.title.isNotEmpty) TextSpan(text: '   ${e.title}'),
                  ])),
                  subtitle: Text([
                    e.tool,
                    t.category(e.category),
                    sev?.label ?? s.severityVaries,
                    if (e.language != ToolLanguage.any) e.language.name,
                    if (locked) s.lockedByConfig,
                    if (state.seenRules.containsKey(e.key)) s.seenInScan,
                    ...e.refs,
                  ].join(' · ')),
                  secondary: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (sev != null) SeverityBadge(sev),
                    if (e.url != null)
                      IconButton(
                        tooltip: tp.documentation,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        onPressed: () => launchUrl(Uri.parse(e.url!)),
                      ),
                  ]),
                ));
          },
        ),
      ),
    ]);
  }
}
