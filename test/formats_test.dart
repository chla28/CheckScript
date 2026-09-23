import 'dart:convert';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late ScriptReport bad;
  setUpAll(() async =>
      bad = await Engine(runner: noTools()).analyzeFile(fixture('bad.sh')));

  test('extensions .sarif et .html', () {
    expect(OutputFormat.fromPath('r.sarif'), OutputFormat.sarif);
    expect(OutputFormat.fromPath('r.sarif.json'), OutputFormat.sarif);
    expect(OutputFormat.fromPath('r.html'), OutputFormat.html);
  });

  group('SARIF 2.1.0', () {
    late Map j;
    setUpAll(() => j = jsonDecode(renderSarif([bad])) as Map);

    test('structure', () {
      expect(j['version'], '2.1.0');
      final run = (j['runs'] as List).single as Map;
      expect(run['tool']['driver']['name'], 'check-script');
      expect((run['results'] as List).length, bad.findings.length);
    });
    test('niveaux, emplacements, empreintes', () {
      final results = (j['runs'][0]['results'] as List).cast<Map>();
      final sec001 = results.firstWhere((r) => r['ruleId'] == 'builtin/SEC001');
      expect(sec001['level'], 'error');
      expect(
          sec001['locations'][0]['physicalLocation']['region']['startLine'], 5);
      expect(sec001['partialFingerprints']['checkScript/v1'], isNotEmpty);
      // Problème « fichier » : ligne 1 (SARIF exige startLine ≥ 1).
      final file = results.firstWhere((r) => r['ruleId'] == 'builtin/ROB001');
      expect(
          file['locations'][0]['physicalLocation']['region']['startLine'], 1);
    });
    test('règles : aide et security-severity', () {
      final rules =
          (j['runs'][0]['tool']['driver']['rules'] as List).cast<Map>();
      final r = rules.firstWhere((r) => r['id'] == 'builtin/SEC001');
      expect(r['help']['text'], isNotEmpty);
      expect(r['properties']['security-severity'], '9.5');
    });
  });

  group('HTML', () {
    test('page autonome, filtres, source annotée, échappement', () {
      final h = renderHtml([bad], const RenderOptions());
      expect(h, startsWith('<!DOCTYPE html>'));
      expect(h, contains('<input type="checkbox" value="security" checked>'));
      expect(h, contains('data-sev="critical"'));
      expect(h, contains('id="s0-L5"'));
      expect(h, isNot(contains('<script src')));
      expect(h, contains('&quot;S3cr3tP@ss&quot;')); // source échappée
      expect(h, contains('prefers-color-scheme:dark'));
    });
    test('multi-scripts : tableau de synthèse', () async {
      final good =
          await Engine(runner: noTools()).analyzeFile(fixture('good.sh'));
      final h = renderHtml([bad, good], const RenderOptions(lang: Lang.en));
      expect(h, contains('Multi-script summary'));
      expect(h, contains('href="#s1"'));
    });
  });

  group('conseils et liens dans les rapports', () {
    test('Markdown : conseil et lien wiki', () {
      final sc = Finding(
          tool: 'shellcheck',
          ruleId: 'SC2086',
          category: Category.robustness,
          severity: Severity.medium,
          line: 3,
          message: 'Double quote');
      final r = enrich([sc], Lang.fr).single;
      expect(r.url, 'https://www.shellcheck.net/wiki/SC2086');
      final md = renderMarkdown([bad], const RenderOptions());
      expect(md, contains('→ _Télécharger dans un fichier'));
    });
    test('terminal --details : conseil affiché', () {
      final t = renderTerminal([bad], const RenderOptions());
      expect(t, contains('→ Lire le secret'));
      expect(renderTerminal([bad], const RenderOptions(maxDetails: 10)),
          isNot(contains('→ Lire le secret')));
    });
    test('comparaison dans le rapport', () async {
      final baseline = Baseline.parse(renderJson([bad]));
      final again = await Engine(runner: noTools(), baseline: baseline)
          .analyzeFile(fixture('bad.sh'));
      final md = renderMarkdown([again], const RenderOptions());
      expect(md, contains('## Comparaison avec la référence'));
      expect(md, contains('nouveaux : 0'));
      expect(md, contains('Aucun problème détecté.'));
      final ad = renderAsciidoc([again], const RenderOptions(lang: Lang.en));
      expect(ad, contains('== Comparison with the baseline'));
      expect(renderTerminal([again], const RenderOptions()), contains('+0,0'));
    });
    test('JSON : profil, suppressions, comparaison', () async {
      final e = Engine(
          runner: noTools(),
          config: CheckConfig.forProfile(Profile.strict)
              .copyWith(contexts: {ExecContext.cron}));
      final r = await e.analyzeFile(fixture('good.sh'));
      final j = (jsonDecode(renderJson([r]))['reports'] as List).single as Map;
      expect(j['profile'], 'strict');
      expect(j['contexts'], ['cron']);
      expect(j['suppressed'], 0);
    });
  });

  group('secrets externes', () {
    test('gitleaks : JSON (après journaux), secret jamais recopié', () {
      const out =
          '12:00AM INF scan completed\n[{"Description":"AWS Access Key",'
          '"StartLine":7,"StartColumn":3,"Secret":"REDACTED","Match":"AKIA…",'
          '"RuleID":"aws-access-token"}]';
      final f = parseGitleaks(out).single;
      expect(f.ruleId, 'GL:aws-access-token');
      expect(f.line, 7);
      expect(f.severity, Severity.critical);
      expect(f.message.contains('AKIA'), isFalse);
      expect(parseGitleaks(''), isEmpty);
      expect(() => parseGitleaks('garbage'), throwsFormatException);
    });
    test('trufflehog : JSON Lines, vérifié / non vérifié', () {
      const out = 'log line\n'
          '{"SourceMetadata":{"Data":{"Filesystem":{"file":"x.sh","line":4}}},'
          '"DetectorName":"Github","Verified":false,"Raw":"ghp_x"}\n'
          '{"SourceMetadata":{"Data":{"Filesystem":{"file":"x.sh","line":9}}},'
          '"DetectorName":"AWS","Verified":true}\n';
      final f = parseTrufflehog(out);
      expect(f.map((x) => (x.ruleId, x.line, x.severity)), [
        ('TH:Github', 4, Severity.high),
        ('TH:AWS', 9, Severity.critical),
      ]);
      expect(f.first.message.contains('ghp_'), isFalse);
    });
    test('trufflehog lancé sans vérification réseau', () async {
      final runner =
          FakeRunner({'trufflehog': (_) => const CommandResult(0, '', '')});
      await Engine(runner: runner).analyze(script('#!/bin/bash\necho a\n'));
      final call = runner.calls.firstWhere((c) => c.$1 == 'trufflehog');
      expect(call.$2, contains('--no-verification'));
    });
    test('doublon avec la règle intégrée SEC002', () {
      final gl =
          parseGitleaks('[{"RuleID":"generic-api-key","StartLine":3}]').single;
      const sec = Finding(
          tool: 'builtin',
          ruleId: 'SEC002',
          category: Category.security,
          severity: Severity.critical,
          line: 3,
          message: 'm');
      expect(deduplicate([gl, sec]), [gl]);
    });
  });

  group('progression et annulation', () {
    test('progression outil par outil jusqu\'à la fin', () async {
      final events = <AnalysisProgress>[];
      await Engine(runner: noTools())
          .analyze(script('#!/bin/bash\necho a\n'), onProgress: events.add);
      expect(events.first.done, 0);
      expect(events.last.tool, isNull);
      expect(events.last.fraction, 1);
      expect(events.where((e) => e.lastRun != null).map((e) => e.lastRun!.tool),
          containsAll(['builtin', 'shellcheck']));
    });
    test('annulation avant le début', () async {
      final token = CancelToken()..cancel();
      expect(
          Engine(runner: noTools()).analyze(script('echo a\n'), cancel: token),
          throwsA(isA<AnalysisCancelled>()));
    });
    test('annulation pendant un outil', () async {
      final token = CancelToken();
      final runner = FakeRunner({
        'bash': (_) {
          token.cancel();
          return const CommandResult(0, '', '');
        },
      });
      expect(Engine(runner: runner).analyze(script('echo a\n'), cancel: token),
          throwsA(isA<AnalysisCancelled>()));
    });
    test('CancelToken : écouteurs', () {
      final t = CancelToken();
      var n = 0;
      final off = t.onCancel(() => n++);
      t.onCancel(() => n += 10);
      off();
      t.cancel();
      t.cancel();
      expect(n, 10);
      t.onCancel(() => n += 100); // déjà annulé : immédiat
      expect(n, 110);
    });
    test('ProcessCommandRunner : entrée standard et processus tué', () async {
      const r = ProcessCommandRunner();
      final res = await r.run('cat', [], stdin: 'bonjour');
      expect(res!.stdout, 'bonjour');
      expect(await r.run('introuvable-xyz', []), isNull);
      final token = CancelToken();
      final f = r.run('sleep', ['5'], cancel: token);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();
      await expectLater(f, throwsA(isA<AnalysisCancelled>()));
    });
  });
}
