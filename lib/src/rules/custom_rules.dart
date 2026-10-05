/// Règles personnalisées, déclarées dans la configuration du projet
/// (`rules.custom` de `.checkscript.yaml`) : conventions maison vérifiées par
/// expression régulière, ligne par ligne.
///
/// ```yaml
/// rules:
///   custom:
///     - id: ACME001
///       pattern: '\bcurl\b[^|]*\|\s*(ba)?sh\b'
///       message: Pas de curl | sh dans nos scripts
///       severity: critical        # critical, high, medium (défaut), low
///       category: security        # défaut : maintainability
///       fix: Télécharger, vérifier la signature, puis exécuter.
///     - id: ACME002
///       pattern: 'set -euo pipefail'
///       absent: true              # signalé si le motif n'apparaît nulle part
///       language: shell           # shell, python ou any (défaut)
///       message: Toujours activer set -euo pipefail
///     - id: ACME003
///       pattern: '\begrep\b'
///       replace: 'grep -E'        # correction automatique ($1… : groupes)
///       message: egrep est obsolète
/// ```
library;

import 'package:yaml/yaml.dart';

import '../analyzers/analyzer.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../script_info.dart';
import 'catalog.dart';

class CustomRule {
  /// Identifiant (majuscules, chiffres, `_` et `-`), distinct des règles
  /// intégrées.
  final String id;
  final RegExp pattern;
  final Tr message;
  final Tr? fix;
  final Severity severity;
  final Category category;
  final ToolLanguage language;

  /// Signalé (ligne 0) quand le motif n'apparaît dans aucune ligne.
  final bool absent;

  /// Remplacement de la correspondance (correction automatique) : `$0`,
  /// `$1`… désignent les groupes.
  final String? replace;

  /// Appliquer aussi aux lignes de commentaire.
  final bool comments;
  final String? url;

  const CustomRule({
    required this.id,
    required this.pattern,
    required this.message,
    this.fix,
    this.severity = Severity.medium,
    this.category = Category.maintainability,
    this.language = ToolLanguage.any,
    this.absent = false,
    this.replace,
    this.comments = false,
    this.url,
  });

  static final _id = RegExp(r'^[A-Z][A-Z0-9_-]{1,31}$');

  /// Relit une règle de la configuration ; lève [FormatException] (message
  /// en français, comme les autres erreurs de configuration).
  factory CustomRule.fromYaml(Object? y) {
    if (y is! YamlMap) {
      throw const FormatException('rules.custom: list of rules expected');
    }
    final id = '${y['id'] ?? ''}'.toUpperCase();
    if (!_id.hasMatch(id)) {
      throw FormatException('rules.custom: invalid identifier "$id" '
          '(uppercase letters, digits, _ and -)');
    }
    if (ruleCatalog.any((r) => r.id == id) || id == 'SYNTAX') {
      throw FormatException('rules.custom: $id is already a built-in rule');
    }
    String where(String key) => 'rules.custom $id: $key';
    final source = y['pattern'];
    if (source is! String || source.isEmpty) {
      throw FormatException(where('pattern missing'));
    }
    final RegExp pattern;
    try {
      pattern = RegExp(source, caseSensitive: y['ignoreCase'] != true);
    } on FormatException catch (e) {
      throw FormatException(where('invalid pattern (${e.message})'));
    }
    Tr? text(String key, {bool required = false}) {
      final v = y[key];
      if (v == null) {
        if (required) throw FormatException(where('$key missing'));
        return null;
      }
      if (v is YamlMap) {
        final fr = v['fr'], en = v['en'];
        if (fr == null && en == null) {
          throw FormatException(where('$key: fr and/or en expected'));
        }
        return Tr('${fr ?? en}', '${en ?? fr}');
      }
      return Tr('$v', '$v');
    }

    T parse<T>(String key, T? Function(String) f, T def) {
      final v = y[key];
      if (v == null) return def;
      return f('$v') ?? (throw FormatException(where('unknown $key: $v')));
    }

    final replace = y['replace'];
    final absent = y['absent'] == true;
    if (absent && replace != null) {
      throw FormatException(where('replace est sans objet avec absent'));
    }
    return CustomRule(
      id: id,
      pattern: pattern,
      message: text('message', required: true)!,
      fix: text('fix'),
      severity: parse('severity', Severity.tryParse, Severity.medium),
      category: parse('category', Category.tryParse, Category.maintainability),
      language: parse(
          'language',
          (s) => ToolLanguage.values
              .where((l) => l.name == s.toLowerCase())
              .firstOrNull,
          ToolLanguage.any),
      absent: absent,
      replace: replace == null ? null : '$replace',
      comments: y['comments'] == true,
      url: y['url'] as String?,
    );
  }

  /// Représentation YAML (une entrée de liste), relisible par [fromYaml].
  List<String> toYaml() {
    String q(String v) =>
        "'${v.replaceAll("'", "''")}'"; // chaîne YAML entre apostrophes
    String tr(Tr t) =>
        t.fr == t.en ? q(t.fr) : '{fr: ${q(t.fr)}, en: ${q(t.en)}}';
    return [
      '- id: $id',
      '  pattern: ${q(pattern.pattern)}',
      if (!pattern.isCaseSensitive) '  ignoreCase: true',
      '  message: ${tr(message)}',
      if (fix != null) '  fix: ${tr(fix!)}',
      '  severity: ${severity.name}',
      '  category: ${category.name}',
      if (language != ToolLanguage.any) '  language: ${language.name}',
      if (absent) '  absent: true',
      if (replace != null) '  replace: ${q(replace!)}',
      if (comments) '  comments: true',
      if (url != null) '  url: ${q(url!)}',
    ];
  }

  /// Texte de remplacement de [m] (`$0`…`$9`, `${nom}`).
  String replacementFor(RegExpMatch m) => replace!.replaceAllMapped(
      RegExp(r'\$(?:(\d)|\{(\w+)\})'),
      (r) => r[1] != null
          ? (int.parse(r[1]!) <= m.groupCount ? m[int.parse(r[1]!)] ?? '' : '')
          : (m.groupNames.contains(r[2]) ? m.namedGroup(r[2]!) ?? '' : ''));

  /// Problèmes de [script] (lignes 1-based).
  List<Finding> check(ScriptInfo script, Lang lang) {
    if (!language.accepts(script)) return const [];
    final out = <Finding>[];
    Finding finding(int line, int column, List<TextEdit> edits) => Finding(
          tool: 'custom',
          ruleId: id,
          category: category,
          severity: severity,
          line: line,
          column: column,
          message: message.of(lang),
          hint: fix?.of(lang),
          url: url,
          edits: edits,
        );
    for (var i = 0; i < script.lines.length; i++) {
      final text = script.lines[i];
      if (text.isEmpty) continue;
      if (!comments && text.trimLeft().startsWith('#')) continue;
      final matches = pattern.allMatches(text).toList();
      if (matches.isEmpty) continue;
      if (absent) return const [];
      out.add(finding(i + 1, matches.first.start + 1, [
        if (replace != null)
          for (final m in matches)
            TextEdit(
                i + 1, m.start + 1, i + 1, m.end + 1, replacementFor(m), id),
      ]));
    }
    return absent ? [finding(0, 0, const [])] : out;
  }
}

/// Analyseur des règles personnalisées de la configuration.
class CustomRulesAnalyzer extends Analyzer {
  @override
  String get name => 'custom';

  @override
  ToolLanguage get language => ToolLanguage.any;

  @override
  Future<AnalyzerResult> analyze(AnalysisContext ctx) async {
    final rules = ctx.config.customRules;
    if (rules.isEmpty) {
      return const AnalyzerResult(
          ToolRun('custom', ToolStatus.skipped, detail: 'rules.custom'));
    }
    final findings = [
      for (final r in rules) ...r.check(ctx.script, ctx.lang),
    ];
    return AnalyzerResult(
        ToolRun('custom', ToolStatus.ok,
            detail: '${rules.length}', findings: findings.length),
        findings);
  }
}
