/// Description complète d'une règle (`check-script explain RÈGLE`) : titre,
/// catégorie, sévérité, références, exemple « à éviter / à écrire »,
/// équivalents dans les autres outils et façons de la désactiver.
library;

import 'analyzers/analyzer.dart' show ToolLanguage;
import 'i18n.dart';
import 'rules/custom_rules.dart';
import 'rules/examples.dart';
import 'rules/registry.dart';
import 'rules/same_rules.dart';

/// Règles connues de même identifiant que [id] (sans casse) : intégrées,
/// codes d'outils classés, règles personnalisées [custom]. Vide si inconnue.
List<RuleEntry> findRules(String id, Lang lang,
    {List<CustomRule> custom = const []}) {
  final key = id.trim().toUpperCase();
  return [
    for (final e in [...knownRules(lang), ...customRuleEntries(custom, lang)])
      if (e.key == key) e
  ];
}

/// Identifiants proches de [id] (même début, ou contenant la saisie), pour
/// aider après une faute de frappe ; au plus [max].
List<String> similarRuleIds(String id, Lang lang,
    {List<CustomRule> custom = const [], int max = 8}) {
  final key = id.trim().toUpperCase();
  if (key.isEmpty) return const [];
  final ids = {
    for (final e in [...knownRules(lang), ...customRuleEntries(custom, lang)])
      e.key
  }.toList()
    ..sort();
  final prefix = key.length >= 3 ? key.substring(0, key.length - 1) : key;
  final out = [
    for (final i in ids)
      if (i.startsWith(prefix) || i.contains(key)) i
  ];
  return out.take(max).toList();
}

/// Texte de la description de la règle [e].
String renderRuleDoc(RuleEntry e, Lang lang) {
  String t(String fr, String en) => lang == Lang.fr ? fr : en;
  final m = Messages(lang);
  final b = StringBuffer();
  b.writeln('${e.id}${e.title.isEmpty ? '' : ' — ${e.title}'}');
  b.writeln();
  final lng = switch (e.language) {
    ToolLanguage.shell => 'shell',
    ToolLanguage.python => 'python',
    ToolLanguage.any => t('shell, python', 'shell, python'),
  };
  b.writeln('${t('Catégorie', 'Category')} : ${m.category(e.category)}');
  b.writeln('${t('Sévérité', 'Severity')} : '
      '${e.severity?.label ?? t('variable (selon l\'outil)', 'varies (by tool)')}');
  b.writeln('${t('Outil', 'Tool')} : ${e.tool}');
  b.writeln('${t('Langage', 'Language')} : $lng');
  if (e.refs.isNotEmpty) {
    b.writeln('${t('Références', 'References')} : ${e.refs.join(' · ')}');
  }
  if (e.url != null) {
    b.writeln('${t('Documentation', 'Documentation')} : ${e.url}');
  }
  final same = sameRuleIds(e.id).toList()..sort();
  if (same.isNotEmpty) {
    b.writeln(
        '${t('Équivalents dans d\'autres outils', 'Equivalent in other tools')}'
        ' : ${same.join(', ')}');
  }
  final ex = exampleFor(e.id);
  if (ex != null) {
    String indent(String code) =>
        code.trimRight().split('\n').map((l) => '    $l').join('\n');
    b.writeln();
    b.writeln('${t('À éviter', 'Avoid')} :');
    b.writeln(indent(ex.badOf(lang)));
    b.writeln();
    b.writeln('${t('À écrire', 'Write instead')} :');
    b.writeln(indent(ex.goodOf(lang)));
  } else {
    b.writeln();
    b.writeln(t('Pas d\'exemple rédigé pour cette règle.',
        'No example written for this rule.'));
  }
  b.writeln();
  b.writeln('${t('Pour l\'ignorer', 'To ignore it')} :');
  b.writeln(t(
      '  - ce cas : # check-script disable=${e.id}  (ligne ou ligne suivante)',
      '  - this case: # check-script disable=${e.id}  (line or next line)'));
  b.writeln(t('  - ce fichier : # check-script disable-file=${e.id}',
      '  - this file: # check-script disable-file=${e.id}'));
  b.writeln(t('  - partout : rules.disabled: [${e.id}] dans .checkscript.yaml',
      '  - everywhere: rules.disabled: [${e.id}] in .checkscript.yaml'));
  return b.toString();
}
