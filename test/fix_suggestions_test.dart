import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Finding _f(String rule, int line,
        {String tool = 'builtin',
        String? snippet = '',
        List<TextEdit> edits = const []}) =>
    Finding(
        tool: tool,
        ruleId: rule,
        category: Category.robustness,
        severity: Severity.low,
        line: line,
        message: rule,
        snippet: snippet,
        edits: edits);

void main() {
  group('corrections par problème', () {
    test('ShellCheck : remplacements joints à chaque problème', () {
      final fs =
          parseShellcheckJson(readFixture('outputs/shellcheck_fixable.json'));
      final cd = fs.firstWhere((f) => f.ruleId == 'SC2164');
      expect(cd.edits.single.replacement, ' || exit');
      expect(fs.firstWhere((f) => f.ruleId == 'SC2045').edits, isEmpty);
    });

    test('corrections intégrées limitées à la règle et à la ligne', () {
      final lines = [
        'x=`date` ',
        'egrep a f # which',
        'while read l; do :; done'
      ];
      final out = attachFixes([
        _f('POR005', 2),
        _f('SC2162', 3, tool: 'shellcheck'),
        _f('MNT010', 1)
      ], lines);
      expect(fixPreview(out[0], lines), (2, lines[1], 'grep -E a f # which'));
      expect(fixPreview(out[1], lines)!.$3, 'while read -r l; do :; done');
      // Seuls les espaces finaux : les backticks de la même ligne restent.
      expect(fixPreview(out[2], lines)!.$3, 'x=`date`');
    });

    test('pas de correction : heredoc, ligne masquée, règle sans correcteur',
        () {
      final lines = ["cat <<'EOF'", 'egrep a', 'EOF', 'egrep b'];
      final out = attachFixes([
        _f('POR005', 2),
        _f('POR005', 4, snippet: null),
        _f('SEC003', 4),
      ], lines);
      expect(out.every((f) => f.edits.isEmpty), isTrue);
    });

    test('une correction ShellCheck existante est conservée', () {
      const e = TextEdit(1, 1, 1, 6, 'grep -E', 'SC2196');
      final out = attachFixes([
        _f('SC2196', 1, tool: 'shellcheck', edits: const [e])
      ], [
        'egrep a'
      ]);
      expect(out.single.edits, [e]);
    });

    test('aperçu : insertions multiples, sans correction → null', () {
      final f = _f('SC2086', 1, edits: const [
        TextEdit(1, 6, 1, 6, '"', 'SC2086'),
        TextEdit(1, 8, 1, 8, '"', 'SC2086'),
      ]);
      expect(fixPreview(f, ['echo \$x']), (1, 'echo \$x', 'echo "\$x"'));
      expect(fixPreview(_f('SEC003', 1), ['eval x']), isNull);
    });

    test('JSON : les corrections sont conservées', () {
      final f = _f('SC2164', 3,
          edits: const [TextEdit(3, 12, 3, 12, ' || exit', 'SC2164')]);
      final g = Finding.fromJson(f.toJson());
      expect(g.edits.single.replacement, ' || exit');
      expect(g.edits.single.rule, 'SC2164');
      expect(_f('X', 1).toJson().containsKey('edits'), isFalse);
    });

    test('ligne à secret : correction retirée', () {
      final lines = ['#!/bin/bash', 'PASSWORD=S3cr3tP4ss; echo \$PASSWORD'];
      final out = attachSource([
        _f('SEC002', 2),
        _f('SC2086', 2,
            tool: 'shellcheck',
            edits: const [TextEdit(2, 27, 2, 27, '"', 'SC2086')]),
      ], lines);
      expect(out.every((f) => f.snippet == null && f.edits.isEmpty), isTrue);
    });

    test('moteur : corrections jointes au rapport', () async {
      final r = await Engine(runner: noTools(), lang: Lang.en)
          .analyze(script('#!/bin/bash\nset -euo pipefail\negrep a f\n'));
      final f = r.findings.firstWhere((f) => f.ruleId == 'POR005');
      expect(fixPreview(f, r.script.lines)!.$3, 'grep -E a f');
    });
  });

  group('exemples de correction', () {
    test('chaque règle intégrée a un exemple distinct du code fautif', () {
      for (final r in ruleCatalog) {
        final ex = exampleFor(r.id);
        expect(ex, isNotNull, reason: r.id);
        for (final l in Lang.values) {
          expect(ex!.goodOf(l), isNot(ex.badOf(l)), reason: r.id);
        }
      }
    });

    test('alias ShellCheck et variantes anglaises', () {
      expect(exampleFor('SC2164'), same(exampleFor('ROB005')));
      expect(exampleFor('SC2086'), isNotNull);
      expect(exampleFor('E003'), isNull);
      final ex = exampleFor('MNT004')!;
      expect(ex.goodOf(Lang.fr), contains('Sauvegarde'));
      expect(ex.goodOf(Lang.en), contains('backup'));
      expect(exampleFor('ROB005')!.goodOf(Lang.en), 'cd /opt/app || exit 1');
    });
  });

  group('rapport HTML', () {
    test('correction proposée ou exemple', () async {
      final r = await Engine(runner: noTools(), lang: Lang.en).analyze(
          script('#!/bin/bash\nset -euo pipefail\negrep a f\neval "\$1"\n'));
      final html = renderHtml([r], const RenderOptions(lang: Lang.en));
      expect(html, contains('Suggested fix'));
      expect(html, contains('<span class="add">+ grep -E a f</span>'));
      expect(html, contains('Fix example'));
      expect(html, contains('Write instead'));
    });
  });
}
