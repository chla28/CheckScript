import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('corrections ShellCheck', () {
    test('lecture des remplacements (sortie réelle)', () {
      final edits =
          parseShellcheckFixes(readFixture('outputs/shellcheck_fixable.json'));
      expect(edits.map((e) => e.rule).toSet(),
          containsAll(['SC2164', 'SC2086', 'SC2006']));
    });
    test('application sans chevauchement', () {
      final (t, c) = applyEdits('echo \$x\n', const [
        TextEdit(1, 6, 1, 6, '"', 'SC2086'),
        TextEdit(1, 8, 1, 8, '"', 'SC2086'),
      ]);
      expect(t, 'echo "\$x"\n');
      expect(c, {'SC2086': 1});
      final (t2, _) = applyEdits('abcdef', const [
        TextEdit(1, 1, 1, 4, 'X', 'A'),
        TextEdit(1, 3, 1, 5, 'Y', 'B'), // chevauche : ignoré
      ]);
      expect(t2, 'Xdef');
    });
    test('fichier réel', () {
      final (t, _) = applyEdits(readFixture('fixable.sh'),
          parseShellcheckFixes(readFixture('outputs/shellcheck_fixable.json')));
      expect(t, contains('cd /opt/app || exit'));
      expect(t, contains('egrep x "\$f"'));
    });
  });

  group('corrections intégrées', () {
    test('egrep, which, read, espaces finaux, backticks', () {
      final (t, c) = applyBuiltinFixes(
          'x=`date`\negrep a f   \nif which ls; then :; fi\nwhile read l; do :; done\n');
      expect(t,
          'x=\$(date)\ngrep -E a f\nif command -v ls; then :; fi\nwhile read -r l; do :; done\n');
      expect(
          c, {'MNT007': 1, 'MNT010': 1, 'POR005': 1, 'POR004': 1, 'ROB007': 1});
    });
    test('heredocs, chaînes et commentaires intacts', () {
      const src = "cat <<'EOF'\negrep   \nEOF\necho 'which `x`' # egrep\n";
      final (t, c) = applyBuiltinFixes(src);
      expect(t, src);
      expect(c, isEmpty);
    });
    test('backticks avec antislash conservés', () {
      expect(replaceBackticks(r'a=`echo \`x\``').$2, 0);
      expect(replaceBackticks('"`date`"'), (r'"$(date)"', 1));
    });
  });

  group('fixScript', () {
    test('sans outils : corrections intégrées seules', () async {
      final r = await fixScript(script('#!/bin/bash\negrep a f\n'),
          runner: noTools());
      expect(r.changed, isTrue);
      expect(r.fixed, '#!/bin/bash\ngrep -E a f\n');
      expect(r.applied, {'POR005': 1});
    });
    test('CRLF normalisé et signalé', () async {
      final r =
          await fixScript(script('#!/bin/sh\r\necho a\r\n'), runner: noTools());
      expect(r.fixed, '#!/bin/sh\necho a\n');
      expect(r.applied['ROB009'], 1);
    });
    test('shfmt appliqué sur l\'entrée standard', () async {
      final runner = FakeRunner({
        'shfmt': (_) =>
            const CommandResult(0, '#!/bin/bash\nif a; then\n  b\nfi\n', ''),
      });
      final r = await fixScript(script('#!/bin/bash\nif a; then\nb\nfi\n'),
          runner: runner);
      expect(r.applied['FORMAT'], 1);
      final i = runner.calls.indexWhere((c) => c.$1 == 'shfmt');
      expect(runner.stdins[i], contains('if a; then'));
    });
    test('abandon si la syntaxe devient invalide', () async {
      // bash -n : valide avant, invalide après.
      var calls = 0;
      final r2 = await fixScript(script('#!/bin/bash\nif a; then b; fi\n'),
          runner: FakeRunner({
            'shfmt': (_) =>
                const CommandResult(0, '#!/bin/bash\nif a; then\n', ''),
            'bash': (_) => ++calls == 1
                ? const CommandResult(0, '', '')
                : const CommandResult(2, '', 'syntax error'),
          }));
      expect(r2.aborted, 'syntax error');
      expect(r2.changed, isFalse);
    });
  });

  group('diff unifié', () {
    test('identiques : vide', () => expect(unifiedDiff('a\n', 'a\n'), isEmpty));
    test('modification simple', () {
      final d =
          unifiedDiff('a\nb\nc\n', 'a\nB\nc\n', fromName: 'x', toName: 'y');
      expect(d, '--- x\n+++ y\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n');
    });
    test('blocs séparés au-delà du contexte', () {
      final a = List.generate(20, (i) => 'l$i').join('\n');
      final b = a.replaceFirst('l1\n', 'X\n').replaceFirst('l18', 'Y');
      final d = unifiedDiff(a, b);
      expect('@@'.allMatches(d).length, 4); // deux en-têtes de bloc
    });
    test('ajout en fin et suppression', () {
      expect(unifiedDiff('a\n', 'a\nb\n'), contains('+b'));
      expect(unifiedDiff('a\nb\n', 'a\n'), contains('-b'));
      expect(unifiedDiff('', 'a\n'), contains('@@ -0,0 +1,1 @@'));
    });
  });
}
