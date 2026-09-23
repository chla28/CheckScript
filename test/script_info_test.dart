import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('dialectFromShebang', () {
    final cases = {
      '#!/bin/sh': Dialect.sh,
      '#!/bin/bash': Dialect.bash,
      '#!/usr/bin/env bash': Dialect.bash,
      '#!/usr/bin/env -S bash -e': Dialect.bash,
      '#! /bin/dash': Dialect.dash,
      '#!/bin/ksh93': Dialect.ksh,
      '#!/usr/bin/zsh': Dialect.zsh,
      '#!/usr/bin/python3': Dialect.unknown,
    };
    cases.forEach((shebang, expected) {
      test(shebang, () {
        expect(ScriptInfo.dialectFromShebang(shebang), expected);
      });
    });
    test('pas de shebang', () {
      expect(ScriptInfo.dialectFromShebang(null), Dialect.unknown);
    });
  });

  test('métriques de lignes', () {
    final s = script('#!/bin/sh\n# commentaire\n\necho a\n  # autre\necho b\n');
    expect(s.totalLines, 6);
    expect(s.codeLines, 2);
    expect(s.commentLines, 2);
    expect(s.shebang, '#!/bin/sh');
    expect(s.dialect, Dialect.sh);
  });

  test('CRLF détecté et normalisé', () {
    final s = script('#!/bin/sh\r\necho a\r\n');
    expect(s.hasCrlf, isTrue);
    expect(s.lines, ['#!/bin/sh', 'echo a']);
  });

  test('dialecte forcé', () {
    expect(script('#!/bin/sh\n', dialect: Dialect.bash).dialect, Dialect.bash);
  });

  test('Dialect.isPosix', () {
    expect(Dialect.sh.isPosix, isTrue);
    expect(Dialect.dash.isPosix, isTrue);
    expect(Dialect.bash.isPosix, isFalse);
  });
}
