import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Les sorties analysées ici ont été produites par les vrais outils
/// (shellcheck 0.11, shfmt 3.14, bashate 2.1, checkbashisms devscripts,
/// bash 5) : voir test/fixtures/outputs/.
void main() {
  group('ShellCheck', () {
    test('json1 : codes, lignes et classement', () {
      final f = parseShellcheckJson(readFixture('outputs/shellcheck_bad.json'));
      expect(f, isNotEmpty);
      final cd = f.firstWhere((x) => x.ruleId == 'SC2164');
      expect(cd.line, 2);
      expect(cd.category, Category.robustness);
      expect(cd.severity, Severity.high);
      final rm = f.firstWhere((x) => x.ruleId == 'SC2115');
      expect(
          (rm.category, rm.severity), (Category.security, Severity.critical));
      expect(f.every((x) => x.tool == 'shellcheck'), isTrue);
    });

    test('SC3xxx classés en portabilité', () {
      final f =
          parseShellcheckJson(readFixture('outputs/shellcheck_posix.json'));
      final sc3 = f.where((x) => x.ruleId.startsWith('SC3'));
      expect(sc3, isNotEmpty);
      expect(sc3.every((x) => x.category == Category.portability), isTrue);
    });

    test('classement par défaut selon le niveau', () {
      expect(classifyShellcheck(9999, 'error'),
          (Category.robustness, Severity.high));
      expect(classifyShellcheck(9999, 'warning'),
          (Category.robustness, Severity.medium));
      expect(classifyShellcheck(9999, 'info'),
          (Category.robustness, Severity.low));
      expect(classifyShellcheck(9999, 'style'),
          (Category.maintainability, Severity.low));
      expect(classifyShellcheck(1089, 'error'),
          (Category.robustness, Severity.high));
      expect(classifyShellcheck(3043, 'warning'),
          (Category.portability, Severity.medium));
    });

    test('bashismes cassant dash classés High (calibrage)', () {
      for (final code in [3010, 3011, 3020, 3030, 2112, 2113]) {
        expect(classifyShellcheck(code, 'warning'),
            (Category.portability, Severity.high),
            reason: 'SC$code');
      }
      // local est pris en charge par dash : reste Medium.
      expect(classifyShellcheck(3043, 'warning').$2, Severity.medium);
    });

    test('ancien format json (liste) et sortie vide', () {
      expect(parseShellcheckJson(''), isEmpty);
      final f = parseShellcheckJson(
          '[{"line":3,"column":1,"level":"style","code":2006,"message":"m"}]');
      expect(f.single.ruleId, 'SC2006');
    });

    test('JSON invalide', () {
      expect(() => parseShellcheckJson('{oops'), throwsFormatException);
    });
  });

  group('shfmt', () {
    test('diff : un problème par bloc, à la première ligne modifiée', () {
      final f = parseShfmtDiff(readFixture('outputs/shfmt_diff.txt'));
      expect(f, hasLength(1));
      expect(f.single.line, 3);
      expect(f.single.message, contains('2 line(s)'));
      expect(f.single.category, Category.maintainability);
    });
    test('erreur de dialecte → portabilité', () {
      final f = parseShfmtErrors(readFixture('outputs/shfmt_posix_err.txt'));
      expect(f.single.ruleId, 'DIALECT');
      expect(f.single.category, Category.portability);
      expect(f.single.line, 5);
    });
    test('erreur de syntaxe → robustesse', () {
      final f =
          parseShfmtErrors('x.sh:5:1: `}` can only be used to close a block');
      expect(f.single.ruleId, 'PARSE');
      expect(f.single.category, Category.robustness);
    });
    test('unité d\'indentation', () {
      expect(indentUnit(['if a; then', '  b', '    c']), 2);
      expect(indentUnit(['if a; then', '    b', '        c']), 4);
      expect(indentUnit(['if a; then', '\tb', '\t\tc']), 0);
      expect(indentUnit(['echo a']), 2);
    });
  });

  group('bashate', () {
    test('format moderne', () {
      final f = parseBashate(readFixture('outputs/bashate_modern.txt'));
      expect(ids(f), {'E001', 'E002', 'E003'});
      expect(f.first.line, 2);
    });
    test('ancien format (0.x)', () {
      final f =
          parseBashate("[E] E040: Syntax error: bad: 'x'\n - t.sh : L7\n");
      expect(f.single.ruleId, 'E040');
      expect(f.single.line, 7);
      expect(f.single.category, Category.robustness);
    });
  });

  test('checkbashisms', () {
    final f =
        parseCheckbashisms(readFixture('outputs/checkbashisms_posix.txt'));
    expect(f.map((x) => x.line), [5, 7, 7, 8]);
    expect(f.first.snippet, 'function show {');
    expect(f.every((x) => x.category == Category.portability), isTrue);
  });

  test('bash -n', () {
    final f = parseSyntaxErrors(readFixture('outputs/bash_n.txt'));
    expect(f, hasLength(1));
    expect(f.single.line, 4);
    expect(f.single.severity, Severity.critical);
  });

  test('dash -n', () {
    final f = parseSyntaxErrors('x.sh: 12: Syntax error: "}" unexpected');
    expect(f.single.line, 12);
  });

  test('version illisible mais outil présent : « ? » (shfmt Fedora)', () async {
    final runner =
        FakeRunner({'shfmt': (_) => const CommandResult(0, '\n', '')});
    expect(await ShfmtAnalyzer().version(runner, const CheckConfig()), '?');
    expect(
        await ShfmtAnalyzer().version(noTools(), const CheckConfig()), isNull);
  });

  test('extractVersion', () {
    expect(extractVersion('bashate: 2.1.1'), '2.1.1');
    expect(extractVersion('v3.14.1'), '3.14.1');
    expect(extractVersion('none'), isNull);
  });
}
