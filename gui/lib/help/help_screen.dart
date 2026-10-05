/// Aide en ligne : liste des sujets (avec recherche) et page du sujet
/// choisi ; aide contextuelle (bouton « ? ») qui renvoie à cet écran.
library;

import 'package:check_script/check_script.dart';
import 'package:flutter/material.dart';

import '../code_style.dart';
import '../strings.dart';
import 'help_content.dart';

/// Permet à un bouton d'aide contextuelle d'ouvrir l'écran d'aide sur un
/// sujet. Absent (tests de widgets isolés) : les boutons « ? » ne s'affichent
/// pas.
class HelpScope extends InheritedWidget {
  const HelpScope({super.key, required this.openHelp, required super.child});

  final void Function(HelpTopic topic) openHelp;

  static HelpScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HelpScope>();

  @override
  bool updateShouldNotify(HelpScope old) => false;
}

/// Petite icône « ? » : un clic montre le résumé du sujet, avec un lien vers
/// la page complète de l'aide.
class HelpButton extends StatelessWidget {
  const HelpButton(this.topic, {super.key, required this.lang});
  final HelpTopic topic;
  final Lang lang;

  @override
  Widget build(BuildContext context) {
    final scope = HelpScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final s = S(lang);
    final page = helpPages(lang).firstWhere((p) => p.topic == topic);
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      tooltip: s.helpOn(page.title),
      icon: const Icon(Icons.help_outline),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(page.title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(page.quick),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(s.close)),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                scope.openHelp(topic);
              },
              child: Text(s.fullHelp),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pages dont le texte contient [query] (toutes si vide), sans tenir compte de
/// la casse.
List<HelpPage> filterHelpPages(List<HelpPage> pages, String query) {
  final q = query.trim().toLowerCase();
  return q.isEmpty
      ? pages
      : [
          for (final p in pages)
            if (p.searchText.contains(q)) p
        ];
}

/// Écran d'aide : sujets à gauche (en liste déroulante si la fenêtre est
/// étroite), page du sujet à droite.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, required this.lang, required this.topic});
  final Lang lang;

  /// Sujet affiché ; modifié par la navigation et par l'aide contextuelle.
  final ValueNotifier<HelpTopic> topic;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.topic.addListener(_onTopic);
  }

  @override
  void dispose() {
    widget.topic.removeListener(_onTopic);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTopic() {
    if (mounted) setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final s = S(widget.lang);
    final all = helpPages(widget.lang);
    final shown = filterHelpPages(all, _search.text);
    final current = all.firstWhere((p) => p.topic == widget.topic.value);

    final searchField = TextField(
      controller: _search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        hintText: s.searchHelp,
        border: const OutlineInputBorder(),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: s.clearSearch,
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(_search.clear),
              ),
      ),
      onChanged: (_) => setState(() {}),
    );

    Widget topics() => shown.isEmpty
        ? Padding(padding: const EdgeInsets.all(16), child: Text(s.noHelpFound))
        : ListView(children: [
            for (final p in shown)
              ListTile(
                dense: true,
                selected: p.topic == current.topic,
                title: Text(p.title),
                onTap: () => widget.topic.value = p.topic,
              ),
          ]);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      final page = _PageView(
          page: current, lang: widget.lang, scroll: _scroll, query: _search);
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 250,
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(12), child: searchField),
              Expanded(child: topics()),
            ]),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ]);
      }
      return Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: searchField),
        SizedBox(
          height: shown.isEmpty ? 56 : 96,
          child: topics(),
        ),
        const Divider(height: 1),
        Expanded(child: page),
      ]);
    });
  }
}

class _PageView extends StatelessWidget {
  const _PageView({
    required this.page,
    required this.lang,
    required this.scroll,
    required this.query,
  });
  final HelpPage page;
  final Lang lang;
  final ScrollController scroll;
  final TextEditingController query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
      child: SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(page.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(page.quick,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (final b in page.blocks) _block(context, b),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _block(BuildContext context, HelpBlock b) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium!;
    switch (b) {
      case HelpHeading(:final text):
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(text, style: theme.textTheme.titleMedium),
        );
      case HelpPara(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(inlineSpans(text, body, context)),
        );
      case HelpBullets(:final items):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 4),
                      Text('•  ', style: body),
                      Expanded(child: Text.rich(inlineSpans(i, body, context))),
                    ]),
              ),
          ]),
        );
      case HelpCode(:final text):
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(text, style: CodeFont.styleOf(context)),
          ),
        );
    }
  }
}

/// Texte avec `**gras**`, `*italique*` et `` `code` `` (mise en forme
/// minimale de l'aide).
TextSpan inlineSpans(String text, TextStyle base, BuildContext context) {
  final theme = Theme.of(context);
  final mono = CodeFont.styleOf(context).copyWith(
      fontSize: (base.fontSize ?? 14) - 1,
      backgroundColor: theme.colorScheme.surfaceContainerHighest);
  final re = RegExp(r'\*\*(.+?)\*\*|`(.+?)`|\*(.+?)\*');
  final spans = <InlineSpan>[];
  var pos = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(text: m.group(2), style: mono));
    } else {
      spans.add(TextSpan(
          text: m.group(3),
          style: const TextStyle(fontStyle: FontStyle.italic)));
    }
    pos = m.end;
  }
  if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
  return TextSpan(style: base, children: spans);
}
