import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Finding fd(String tool, String rule, int line,
        {List<String> eq = const [], Category c = Category.robustness}) =>
    Finding(
        tool: tool,
        ruleId: rule,
        category: c,
        severity: Severity.low,
        line: line,
        message: 'm',
        equivalents: eq);

void main() {
  group('dédoublonnage', () {
    test('règle intégrée supprimée si ShellCheck a signalé l\'équivalent', () {
      final out = deduplicate([
        fd('shellcheck', 'SC2002', 4),
        fd('builtin', 'PERF001', 4, eq: ['SC2002']),
      ]);
      expect(ids(out), {'SC2002'});
    });
    test('pas de suppression sur une autre ligne', () {
      final out = deduplicate([
        fd('shellcheck', 'SC2002', 4),
        fd('builtin', 'PERF001', 5, eq: ['SC2002']),
      ]);
      expect(out, hasLength(2));
    });
    test('motifs avec joker (SC3*)', () {
      final out = deduplicate([
        fd('shellcheck', 'SC3010', 7),
        fd('checkbashisms', 'CB', 7, eq: ['SC3*']),
      ]);
      expect(ids(out), {'SC3010'});
    });
    test('un problème « fichier » (ligne 0) couvre toutes les lignes', () {
      final out = deduplicate([
        fd('builtin', 'MNT004', 0, eq: ['E005']),
        fd('bashate', 'E005', 1),
      ]);
      expect(ids(out), {'MNT004'});
    });
    test('une erreur de syntaxe couvre les SC1xxx de toutes les lignes', () {
      final out = deduplicate([
        fd('syntax', 'SYNTAX', 4, eq: ['SC1*']),
        fd('shellcheck', 'SC1046', 2),
        fd('shellcheck', 'SC2086', 2),
      ]);
      expect(ids(out), {'SYNTAX', 'SC2086'});
    });
    test('même outil, même règle, même ligne : un seul', () {
      expect(
          deduplicate([fd('builtin', 'SEC002', 3), fd('builtin', 'SEC002', 3)]),
          hasLength(1));
    });
  });

  group('configuration appliquée', () {
    test('règle désactivée et reclassement', () {
      const cfg = CheckConfig(
        disabledRules: {'SC2034'},
        overrides: {
          'SC2086':
              RuleOverride(category: Category.security, severity: Severity.high)
        },
      );
      final out = applyConfig(
          [fd('shellcheck', 'SC2034', 1), fd('shellcheck', 'SC2086', 2)], cfg);
      expect(out.single.ruleId, 'SC2086');
      expect(out.single.category, Category.security);
      expect(out.single.severity, Severity.high);
    });
  });

  group('Engine', () {
    test(
        'sans aucun outil externe : règles intégrées seules, outils « absents »',
        () async {
      final e = Engine(runner: noTools(), lang: Lang.en);
      final r = await e.analyze(script(readFixture('bad.sh')));
      final status = {for (final t in r.tools) t.tool: t.status};
      expect(status['builtin'], ToolStatus.ok);
      expect(status['shellcheck'], ToolStatus.missing);
      expect(status['syntax'], ToolStatus.missing);
      expect(ids(r.findings), containsAll(['SEC001', 'SEC002']));
      expect(r.scores, hasLength(5));
      expect(r.score(Category.security).score, lessThan(5));
    });

    test('outil désactivé : non exécuté', () async {
      final runner = FakeRunner({});
      final e = Engine(
          runner: runner,
          config:
              const CheckConfig().withToolsDisabled(['shellcheck', 'syntax']));
      final r = await e.analyze(script('#!/bin/bash\necho a\n'));
      expect(r.tools.firstWhere((t) => t.tool == 'shellcheck').status,
          ToolStatus.disabled);
      expect(runner.calls.map((c) => c.$1), isNot(contains('shellcheck')));
    });

    test('ShellCheck simulé : options transmises, doublons retirés', () async {
      final runner = FakeRunner({
        'shellcheck': (args) => args.contains('--version')
            ? const CommandResult(0, 'ShellCheck\nversion: 0.11.0\n', '')
            : CommandResult(1, readFixture('outputs/shellcheck_bad.json'), ''),
        'bash': (_) => const CommandResult(0, '', ''),
      });
      final e = Engine(runner: runner);
      final r = await e.analyzeFile(fixture('bad.sh'));
      final call = runner.calls.firstWhere((c) => c.$1 == 'shellcheck');
      expect(call.$2,
          containsAll(['--format=json1', '--shell=bash', '--exclude=SC1091']));
      final sc = r.tools.firstWhere((t) => t.tool == 'shellcheck');
      expect(sc.status, ToolStatus.ok);
      expect(sc.version, '0.11.0');
      // SC2164 (cd) couvre ROB005 ; SC2045 couvre ROB008.
      expect(ids(r.findings), containsAll(['SC2164', 'SC2045']));
      expect(ids(r.findings),
          isNot(anyOf(contains('ROB005'), contains('ROB008'))));
    });

    test('erreur de syntaxe remontée en Critical', () async {
      final runner = FakeRunner({
        'bash': (_) => CommandResult(2, '', readFixture('outputs/bash_n.txt')),
      });
      final r =
          await Engine(runner: runner).analyzeFile(fixture('syntax_error.sh'));
      final f = r.findings.firstWhere((f) => f.ruleId == 'SYNTAX');
      expect(f.severity, Severity.critical);
      expect(f.line, 4);
    });

    test('shfmt : échec POSIX accepté en bash → problème de dialecte',
        () async {
      final runner = FakeRunner({
        'shfmt': (args) => args.contains('-ln=posix')
            ? const CommandResult(
                1, '', 'p.sh:10:1: "}" can only be used to close a block')
            : const CommandResult(0, '', ''),
      });
      final r = await Engine(runner: runner).analyzeFile(fixture('posix.sh'));
      final f = r.findings.firstWhere((f) => f.tool == 'shfmt');
      expect(f.ruleId, 'DIALECT');
      expect(f.category, Category.portability);
    });

    test('shfmt : échec en POSIX et en bash → vraie erreur de syntaxe',
        () async {
      final runner = FakeRunner({
        'shfmt': (_) => const CommandResult(
            1, '', 'p.sh:3:1: reached EOF without closing quote'),
      });
      final r = await Engine(runner: runner).analyzeFile(fixture('posix.sh'));
      final f = r.findings.firstWhere((f) => f.tool == 'shfmt');
      expect(f.ruleId, 'PARSE');
      expect(f.category, Category.robustness);
    });

    test('checkbashisms non exécuté sur un script bash', () async {
      final runner =
          FakeRunner({'checkbashisms': (_) => const CommandResult(0, '', '')});
      final r =
          await Engine(runner: runner).analyze(script('#!/bin/bash\necho a\n'));
      expect(r.tools.firstWhere((t) => t.tool == 'checkbashisms').status,
          ToolStatus.skipped);
    });

    test('sortie triée : catégorie, sévérité, ligne', () async {
      final r = await Engine(runner: noTools())
          .analyze(script(readFixture('bad.sh')));
      for (var i = 1; i < r.findings.length; i++) {
        final a = r.findings[i - 1], b = r.findings[i];
        expect(a.category.index <= b.category.index, isTrue);
        if (a.category == b.category) {
          expect(a.severity.index <= b.severity.index, isTrue);
        }
      }
    });
  });
}
