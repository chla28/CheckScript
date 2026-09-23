import 'dart:convert';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late ScriptReport bad;
  late ScriptReport good;

  setUpAll(() async {
    final e = Engine(runner: noTools());
    bad = await e.analyzeFile(fixture('bad.sh'));
    good = await e.analyzeFile(fixture('good.sh'));
  });

  test('format déduit de l\'extension', () {
    expect(OutputFormat.fromPath('r.md'), OutputFormat.markdown);
    expect(OutputFormat.fromPath('R.ADOC'), OutputFormat.asciidoc);
    expect(OutputFormat.fromPath('r.json'), OutputFormat.json);
    expect(OutputFormat.fromPath('r.txt'), OutputFormat.terminal);
    expect(OutputFormat.fromPath('r'), isNull);
  });

  test('Markdown : tableau des 5 catégories avec les 4 sévérités et le total',
      () {
    final md = renderMarkdown([bad], const RenderOptions(lang: Lang.fr));
    expect(md, startsWith('# Évaluation du script : `test/fixtures/bad.sh`'));
    expect(
        md,
        contains(
            '| Catégorie | Note /10 | Critical | High | Medium | Low | Total |'));
    for (final c in [
      'Sécurité',
      'Robustesse',
      'Maintenabilité',
      'Portabilité',
      'Performance'
    ]) {
      expect(md, contains('| $c | **'));
    }
    expect(md, contains('## Détail des problèmes'));
    expect(md, contains('`SEC001`'));
    expect(md, contains('Outils absents'));
  });

  test('Markdown en anglais, sans problème', () {
    final md = renderMarkdown([good], const RenderOptions(lang: Lang.en));
    expect(md, contains('# Script assessment: `test/fixtures/good.sh`'));
    expect(md, contains('| Security | **10.0** | 0 | 0 | 0 | 0 | 0 |'));
    expect(md, contains('No issue detected.'));
  });

  test('Markdown multi-scripts : synthèse en tête', () {
    final md = renderMarkdown([bad, good], const RenderOptions());
    expect(md, startsWith('# Synthèse multi-scripts'));
    expect(md, contains('## Évaluation du script'));
    expect(md, contains('#### Sécurité'));
  });

  test('AsciiDoc : titres et tableaux', () {
    final ad = renderAsciidoc([bad], const RenderOptions());
    expect(ad, startsWith('= Évaluation du script : test/fixtures/bad.sh'));
    expect(ad,
        contains('|Catégorie |Note /10 |Critical |High |Medium |Low |Total'));
    expect(ad, contains('== Détail des problèmes'));
    expect(ad, contains('=== Sécurité'));
    expect('|==='.allMatches(ad).length.isEven, isTrue);
  });

  test('AsciiDoc multi-scripts', () {
    final ad = renderAsciidoc([bad, good], const RenderOptions(lang: Lang.en));
    expect(ad, startsWith('= Multi-script summary'));
    expect(ad, contains('== Script assessment: `test/fixtures/good.sh`'));
    expect(ad, contains('=== Issue details'));
  });

  test('Les | des messages sont échappés', () {
    final md = renderMarkdown([bad], const RenderOptions());
    final line = md.split('\n').firstWhere((l) => l.contains('`SEC001`'));
    expect(line, contains(r'(curl\|sh)'));
  });

  test('JSON structuré', () {
    final j = jsonDecode(renderJson([bad])) as Map;
    final r = (j['reports'] as List).single as Map;
    expect(r['file'], 'test/fixtures/bad.sh');
    expect((r['categories'] as List), hasLength(5));
    expect(
        (r['categories'] as List).first, containsPair('category', 'security'));
    expect((r['findings'] as List), isNotEmpty);
    expect(r['global'], contains('grade'));
  });

  test('Terminal : couleurs optionnelles, détail limité', () {
    final plain = renderTerminal([bad], const RenderOptions(maxDetails: 1));
    expect(plain.contains('\x1B['), isFalse);
    expect(plain, contains('Note globale : '));
    expect(plain, contains('autre(s)'));
    final colored = renderTerminal([bad], const RenderOptions(color: true));
    expect(colored, contains('\x1B['));
    final summary = renderTerminal([bad], const RenderOptions(maxDetails: 0));
    expect(summary.contains('Détail des problèmes'), isFalse);
  });

  test('Notes au format décimal de la langue', () {
    expect(fmtScore(7.5, Lang.fr), '7,5');
    expect(fmtScore(7.5, Lang.en), '7.5');
  });
}
