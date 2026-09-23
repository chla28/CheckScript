import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('fnv1a64 : valeurs de référence', () {
    expect(fnv1a64(''), 'cbf29ce484222325');
    expect(fnv1a64('a'), 'af63dc4c8601ec8c');
  });

  test('empreinte indépendante du numéro de ligne', () async {
    final e = Engine(runner: noTools());
    const body = 'eval "\$x"\n';
    final a =
        await e.analyze(script('#!/bin/bash\n# t\nset -euo pipefail\n$body'));
    final b = await e.analyze(
        script('#!/bin/bash\n# t\nset -euo pipefail\n\n\necho ok\n$body'));
    String fp(ScriptReport r) =>
        r.findings.firstWhere((f) => f.ruleId == 'SEC003').fingerprint!;
    expect(fp(a), fp(b));
  });

  test('occurrences identiques : empreintes distinctes', () {
    final f = Finding(
        tool: 't',
        ruleId: 'R',
        category: Category.security,
        severity: Severity.low,
        line: 1,
        message: 'm');
    final out = fingerprintAll([f, f], ['x']);
    expect(out[0].fingerprint, isNot(out[1].fingerprint));
  });

  test('comparaison : nouveaux, corrigés, inchangés, notes précédentes',
      () async {
    final e = Engine(runner: noTools());
    final before = await e.analyzeFile(fixture('bad.sh'));
    final baseline = Baseline.parse(renderJson([before]));
    final after = await Engine(runner: noTools(), baseline: baseline)
        .analyze(ScriptInfo.fromContent(
            'test/fixtures/bad.sh',
            '${readFixture('bad.sh').replaceFirst('eval "\$USER_CMD"\n', '')}'
                'chmod 666 /etc/app.conf\n'));
    final c = after.comparison!;
    expect(c.added.map((f) => f.ruleId), contains('SEC004'));
    expect(c.fixed, greaterThanOrEqualTo(1)); // SEC003 disparu
    expect(c.unchanged, greaterThan(5));
    expect(c.previousGlobal, before.global);
    expect(c.previousScores[Category.security],
        before.score(Category.security).score);
  });

  test('appariement par nom de fichier si le chemin diffère', () {
    final b = Baseline.parse(
        '{"reports":[{"file":"/old/place/deploy.sh","findings":[]}]}');
    expect(b.entryFor('scripts/deploy.sh'), isNotNull);
    expect(b.entryFor('scripts/other.sh'), isNull);
  });

  test('référence invalide', () {
    expect(() => Baseline.parse('{'), throwsFormatException);
    expect(() => Baseline.parse('{"x":1}'), throwsFormatException);
  });

  test('Finding.fromJson relit toJson', () {
    const f = Finding(
        tool: 'builtin',
        ruleId: 'SEC001',
        category: Category.security,
        severity: Severity.critical,
        line: 4,
        column: 2,
        message: 'm',
        snippet: 's',
        hint: 'h',
        url: 'u',
        fingerprint: 'fp');
    final g = Finding.fromJson(f.toJson());
    expect(g.toJson(), f.toJson());
  });
}
