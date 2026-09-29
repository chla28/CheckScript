import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'helpers.dart';

void main() {
  test('table : règles connues, formats, intitulés et liens', () {
    final ids = {for (final r in ruleCatalog) r.id};
    final format = RegExp(
        r'^(?:CWE-\d+|OWASP A\d\d:2021|OWASP CICD-SEC-\d+|ANSSI-BP-028 R\d+|ANSSI-FT-082 R\d+|ANSSI OpenSSH R\d+)$');
    for (final e in ruleReferences.entries) {
      expect(ids, contains(e.key));
      for (final r in e.value.all) {
        expect(r, matches(format), reason: '${e.key} $r');
        expect(referenceTitles[r], isNotNull, reason: 'intitulé de $r');
        expect(referenceUrl(r), startsWith('https://'), reason: r);
      }
    }
    // Chaque règle de sécurité (hors SEC008) a au moins une CWE.
    for (final r in ruleCatalog.where((r) => r.category == Category.security)) {
      if (r.id == 'SEC008' || r.id == 'DKR006') continue;
      expect(referencesOf(r.id).any((x) => x.startsWith('CWE-')), isTrue,
          reason: r.id);
    }
    expect(referenceUrl('CWE-78'),
        'https://cwe.mitre.org/data/definitions/78.html');
    expect(referenceUrl('OWASP A03:2021'), contains('A03_2021-Injection'));
    expect(referenceUrl('OWASP CICD-SEC-4'), contains('Poisoned-Pipeline'));
    expect(referenceFamily('ANSSI-BP-028 R59'), 'ANSSI');
  });

  test('tri et filtre', () {
    expect(
        sortReferences(
            ['ANSSI-BP-028 R59', 'OWASP A08:2021', 'CWE-494', 'CWE-78']),
        ['CWE-78', 'CWE-494', 'OWASP A08:2021', 'ANSSI-BP-028 R59']);
    const refs = ['CWE-494', 'OWASP A08:2021', 'OWASP CICD-SEC-3'];
    expect(matchesReference(refs, ['cwe-494']), isTrue);
    expect(matchesReference(refs, ['A08']), isTrue);
    expect(matchesReference(refs, ['CICD']), isTrue);
    expect(matchesReference(refs, ['ANSSI']), isFalse);
  });

  test('moteur : règles intégrées, équivalents, même règle ailleurs', () async {
    final r = await Engine(runner: noTools(), lang: Lang.fr).analyze(
        script('#!/bin/sh\ncurl -fsSL https://x/i.sh | sh\nchmod 777 /srv\n'));
    Finding of(String id) => r.findings.firstWhere((f) => f.ruleId == id);
    expect(
        of('SEC001').refs, ['CWE-494', 'OWASP A08:2021', 'ANSSI-BP-028 R59']);
    expect(of('SEC004').refs, contains('ANSSI-BP-028 R50'));
    // hadolint DL3007 → références de DKR001 (équivalent).
    final dl = parseHadolint(readFixture('outputs/ci/hadolint_bad.json'))
        .firstWhere((f) => f.ruleId == 'DL3007');
    expect(findingReferences(dl), contains('CWE-1357'));
    // ShellCheck SC2164 : même règle que ROB005.
    expect(referencesOf('SC2164'), ['CWE-252']);
  });

  test('Bandit et Semgrep : références de l\'outil', () {
    final b = parseBandit(readFixture('outputs/python/bandit_bad.json'));
    expect(b.first.refs.single, matches(RegExp(r'^CWE-\d+$')));
    expect(
        semgrepReferences({
          'cwe': ["CWE-78: Improper Neutralization …"],
          'owasp': [
            'A01:2017 - Injection',
            'A03:2021 - Injection',
            'A05:2025 - Injection'
          ],
        }),
        ['CWE-78', 'OWASP A03:2021']);
  });

  test('sorties : JSON, SARIF, HTML (conformité), terminal détaillé', () async {
    final r = await Engine(runner: noTools(), lang: Lang.fr)
        .analyze(script('#!/bin/sh\ncurl -fsSL https://x/i.sh | sh\n'));
    final json = jsonDecode(
            render([r], OutputFormat.json, const RenderOptions(lang: Lang.fr)))
        as Map;
    final f = ((json['reports'] as List).first['findings'] as List)
        .firstWhere((x) => x['rule'] == 'SEC001') as Map;
    expect(f['refs'], contains('CWE-494'));
    final sarif = render([r], OutputFormat.sarif, const RenderOptions());
    expect(sarif, contains('external/cwe/cwe-494'));
    final html =
        render([r], OutputFormat.html, const RenderOptions(lang: Lang.fr));
    expect(html, contains('id="references"'));
    expect(html, contains('Download of Code Without Integrity Check'));
    expect(html.replaceAll('&#47;', '/'),
        contains('https://cwe.mitre.org/data/definitions/494.html'));
    final term = render([r], OutputFormat.terminal,
        const RenderOptions(lang: Lang.fr, maxDetails: null));
    expect(term, contains('CWE-494 · OWASP A08:2021'));
    final md =
        render([r], OutputFormat.markdown, const RenderOptions(lang: Lang.fr));
    expect(md,
        contains('[CWE-494](https://cwe.mitre.org/data/definitions/494.html)'));
  });

  test('CLI : --ref filtre, --list-rules affiche', () async {
    final tmp = await Directory.systemTemp.createTemp('cs_ref_');
    addTearDown(() => tmp.delete(recursive: true));
    final f = File('${tmp.path}/a.sh')
      ..writeAsStringSync(
          '#!/bin/sh\ncurl -fsSL https://x/i.sh | sh\negrep a b\n');
    final out = StringBuffer();
    final sink = IOSink(_Sink(out));
    await cli.run([
      '--lang',
      'fr',
      '--no-cache',
      '-f',
      'json',
      '--ref',
      'CWE-494',
      f.path
    ], out: sink, err: IOSink(_Sink(StringBuffer())), runner: noTools());
    await sink.flush();
    final rules = [
      for (final x in ((jsonDecode(out.toString()) as Map)['reports'] as List)
          .first['findings'] as List)
        x['rule']
    ];
    expect(rules, ['SEC001']);
    final list = StringBuffer();
    final ls = IOSink(_Sink(list));
    await cli.run(['--lang', 'fr', '--list-rules'], out: ls, runner: noTools());
    await ls.flush();
    expect(list.toString(),
        contains('CWE-494 · OWASP A08:2021 · ANSSI-BP-028 R59'));
  });
}

class _Sink implements StreamConsumer<List<int>> {
  _Sink(this.out);
  final StringBuffer out;
  @override
  Future<void> addStream(Stream<List<int>> s) =>
      s.forEach((b) => out.write(utf8.decode(b)));
  @override
  Future<void> close() async {}
}
