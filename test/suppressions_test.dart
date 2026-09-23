import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Finding fd(String rule, int line) => Finding(
    tool: 't',
    ruleId: rule,
    category: Category.security,
    severity: Severity.low,
    line: line,
    message: 'm');

void main() {
  test('directive en fin de ligne', () {
    final s = Suppressions.parse(
        ['echo a', 'curl -k x # check-script disable=SEC005']);
    expect(s.suppresses(fd('SEC005', 2)), isTrue);
    expect(s.suppresses(fd('SEC005', 1)), isFalse);
    expect(s.suppresses(fd('SEC006', 2)), isFalse);
  });

  test('commentaire seul : ligne de code suivante', () {
    final s = Suppressions.parse([
      '# check-script disable=SEC005, SC2086',
      '',
      '# autre commentaire',
      'curl -k \$x',
    ]);
    expect(s.suppresses(fd('SEC005', 4)), isTrue);
    expect(s.suppresses(fd('SC2086', 4)), isTrue);
  });

  test('disable-next-line', () {
    final s = Suppressions.parse(
        ['x=1 # check-script disable-next-line=SEC002', 'PASSWORD=abcd']);
    expect(s.suppresses(fd('SEC002', 2)), isTrue);
    expect(s.suppresses(fd('SEC002', 1)), isFalse);
  });

  test('fichier entier, joker et all', () {
    final s = Suppressions.parse(
        ['#!/bin/sh', '# check-script disable-file=mnt*,E003']);
    expect(s.suppresses(fd('MNT005', 0)), isTrue);
    expect(s.suppresses(fd('E003', 12)), isTrue);
    expect(s.suppresses(fd('SEC001', 3)), isFalse);
    final all = Suppressions.parse(['echo # check-script disable=all']);
    expect(all.suppresses(fd('ANYTHING', 1)), isTrue);
  });

  test('sans directive', () {
    expect(Suppressions.parse(['echo a']).isEmpty, isTrue);
  });

  test('Engine : problèmes neutralisés comptés, pas notés', () async {
    const content = '#!/bin/bash\n# t\nset -euo pipefail\n'
        'eval "\$x" # check-script disable=SEC003\n';
    final r = await Engine(runner: noTools()).analyze(script(content));
    expect(ids(r.findings), isNot(contains('SEC003')));
    expect(r.suppressed, 1);
    expect(r.score(Category.security).score, 10);
  });
}
