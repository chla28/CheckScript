import 'package:check_script/src/analyzers/shell_lexer.dart';
import 'package:test/test.dart';

void main() {
  test('retire les commentaires mais pas les # dans les chaînes ou \$#', () {
    final l = lexScript([
      'echo a # commentaire',
      'echo "a # pas un commentaire"',
      r'echo $# ${#x}',
    ]);
    expect(l[0].code.trim(), 'echo a');
    expect(l[1].code, 'echo "a # pas un commentaire"');
    expect(l[2].code, r'echo $# ${#x}');
  });

  test('masque le contenu des chaînes et des \${…} dans bare', () {
    final l = lexScript([r'if [ "$x" = "fi done" ]; then echo ${y:-if}; fi']);
    expect(l[0].bare.contains('done'), isFalse);
    expect(l[0].bare.contains('if'), isTrue);
    expect(l[0].bare.length, l[0].code.length);
  });

  test('repère les corps de heredoc (<<, <<-, délimiteur quoté)', () {
    final l = lexScript([
      "cat <<'EOF'",
      'rm -rf / # dans le heredoc',
      'EOF',
      'cat <<-END',
      '\tligne',
      '\tEND',
      'echo fin',
    ]);
    expect([for (final x in l) x.inHeredoc],
        [false, true, true, false, true, true, false]);
    expect(l[1].code, isEmpty);
  });

  test('<<< (here-string) n\'ouvre pas de heredoc', () {
    final l = lexScript(['grep a <<< "\$x"', 'echo b']);
    expect(l[1].inHeredoc, isFalse);
  });

  test('chaîne sur plusieurs lignes', () {
    final l = lexScript(['echo "début', 'fi # suite', 'fin"', 'echo x # c']);
    expect(l[1].continuesString, isTrue);
    expect(l[1].bare.contains('fi'), isFalse);
    expect(l[3].code.trim(), 'echo x');
  });
}
