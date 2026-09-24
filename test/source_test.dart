import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Finding _f(String rule, int line,
        {String tool = 'shellcheck', int column = 0}) =>
    Finding(
        tool: tool,
        ruleId: rule,
        category: Category.robustness,
        severity: Severity.high,
        line: line,
        column: column,
        message: 'm');

void main() {
  const lines = ['#!/bin/bash', 'TOKEN="abcdefgh1234"', '\tcd \$1'];

  test('chaque problème reçoit sa ligne de code', () {
    final fs = attachSource([_f('SC2164', 3), _f('X', 0), _f('Y', 99)], lines);
    expect(fs[0].snippet, '\tcd \$1');
    expect(fs[1].snippet, isNull);
    expect(fs[2].snippet, isNull);
  });

  test('une ligne portant un secret est masquée pour tous ses problèmes', () {
    final secret = _f('SEC002', 2, tool: 'builtin');
    final other = _f('SC2034', 2);
    expect(attachSource([secret, other], lines).map((f) => f.snippet),
        everyElement(isNull));
    // Secret écarté (directive) : la ligne reste masquée.
    expect(
        attachSource([other], lines, detected: [secret, other]).single.snippet,
        isNull);
    expect(
        attachSource([_f('GL:x', 2, tool: 'gitleaks'), other], lines)
            .last
            .snippet,
        isNull);
  });

  test('terminal : ligne sous le problème et repère sous la colonne', () async {
    final r = await Engine(runner: noTools())
        .analyze(script('#!/bin/bash\n\teval "\$1"\n'));
    final out = renderTerminal([r], const RenderOptions());
    expect(out, contains('    2 │ eval "\$1"'));
    final hidden = renderTerminal([r], const RenderOptions(showSource: false));
    expect(hidden, isNot(contains('│ eval')));
  });

  test('repère aligné malgré l\'indentation retirée', () {
    final r = ScriptReport(
      script: script('#!/bin/bash\n\t\tcd \$1\n'),
      tools: const [],
      findings: attachSource(
          [_f('SC2086', 2, column: 6)], ['#!/bin/bash', '\t\tcd \$1']),
      scores: [for (final c in Category.values) CategoryScore(c, 10, const {})],
      global: 10,
      date: DateTime(2026),
    );
    final out = renderTerminal([r], const RenderOptions()).split('\n');
    final i = out.indexWhere((l) => l.endsWith('│ cd \$1'));
    expect(out[i + 1].indexOf('^'), out[i].indexOf('\$1'));
  });
}
