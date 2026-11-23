import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

/// Texte et genre de chaque jeton, pour des attentes lisibles.
List<String> show(List<String> lines, HighlightLanguage lang) {
  final tokens = highlightLines(lines, lang);
  return [
    for (var i = 0; i < lines.length; i++)
      for (final t in tokens[i])
        '${i + 1}:${t.kind.name}:${lines[i].substring(t.start, t.end)}'
  ];
}

void main() {
  test('jetons triés, sans chevauchement, dans la ligne', () {
    const src = [
      '#!/bin/bash',
      'x=1; echo "a \$x \${y:-z}" \'b\' # fin',
      'if [[ -n \$1 ]]; then f() { cat <<-EOF; }; fi',
      '\tcorps \$x',
      '\tEOF',
      'echo "multi',
      'ligne"',
    ];
    for (final lang in HighlightLanguage.values) {
      final all = highlightLines(src, lang);
      expect(all, hasLength(src.length));
      for (var i = 0; i < src.length; i++) {
        var end = 0;
        for (final t in all[i]) {
          expect(t.start, greaterThanOrEqualTo(end), reason: '$lang $i $t');
          expect(t.end, lessThanOrEqualTo(src[i].length));
          end = t.end;
        }
      }
    }
  });

  test('Perl, Ruby, Lua, Node.js : commentaires, chaînes, mots-clés', () {
    expect(
        show([r'my $x = "a"; # fin', r'my $n = $#list;'],
            HighlightLanguage.perl),
        [
          '1:keyword:my',
          '1:variable:\$x',
          '1:string:"a"',
          '1:comment:# fin',
          '2:keyword:my',
          '2:variable:\$n',
          '2:variable:\$#list',
        ]);
    expect(show(['puts "x" # c'], HighlightLanguage.ruby),
        ['1:keyword:puts', '1:string:"x"', '1:comment:# c']);
    expect(
        show(['local a = 1 -- c', '--[[ bloc', 'fin ]] x = 2'],
            HighlightLanguage.lua),
        [
          '1:keyword:local',
          '1:number:1',
          '1:comment:-- c',
          '2:comment:--[[ bloc',
          '3:comment:fin ]]',
          '3:number:2',
        ]);
    expect(
        show(['const a = `x`; // c', '/* b', 'c */ let d;'],
            HighlightLanguage.node),
        [
          '1:keyword:const',
          '1:string:`x`',
          '1:comment:// c',
          '2:comment:/* b',
          '3:comment:c */',
          '3:keyword:let',
        ]);
  });

  test('unités systemd, crontab et sudoers', () {
    expect(
        show(['[Service]', 'ExecStart=/bin/a', '; c'], HighlightLanguage.admin),
        ['1:key:[Service]', '2:key:ExecStart', '3:comment:; c']);
    expect(show(['0 3 * * * /bin/a', '@daily /bin/b'], HighlightLanguage.admin),
        ['1:number:0 3 * * *', '2:number:@daily']);
    expect(show(['alice ALL=(ALL) NOPASSWD: ALL'], HighlightLanguage.admin), [
      '1:keyword:ALL',
      '1:keyword:ALL',
      '1:keyword:NOPASSWD',
      '1:keyword:ALL'
    ]);
  });

  test('langage d\'affichage selon le dialecte', () {
    HighlightLanguage of(String path) =>
        HighlightLanguage.of(ScriptInfo.fromContent(path, 'x\n'));
    expect(of('a.pl'), HighlightLanguage.perl);
    expect(of('a.rb'), HighlightLanguage.ruby);
    expect(of('a.lua'), HighlightLanguage.lua);
    expect(of('a.js'), HighlightLanguage.node);
    expect(of('a.service'), HighlightLanguage.admin);
    expect(of('/etc/sudoers'), HighlightLanguage.admin);
  });

  test('shell : shebang, variables, chaînes, commentaires, mots-clés', () {
    final s = show([
      '#!/bin/bash',
      'x=1; echo "a \$x" \'\$b\' # fin',
      'if [ -n "\$1" ]; then exit 2; fi',
      'deploy() {',
    ], HighlightLanguage.shell);
    expect(s, contains('1:shebang:#!/bin/bash'));
    expect(s, contains('2:variable:x'));
    expect(s, contains('2:builtin:echo'));
    expect(s, contains('2:string:"a '));
    expect(s, contains('2:variable:\$x'));
    expect(s, contains("2:string:'\$b'")); // pas d'expansion entre '
    expect(s, contains('2:comment:# fin'));
    expect(s, contains('3:keyword:if'));
    expect(s, contains('3:keyword:then'));
    expect(s, contains('3:number:2'));
    expect(s, contains('4:function:deploy'));
  });

  test('shell : heredoc et chaîne sur plusieurs lignes', () {
    final s = show([
      'cat <<-"EOF" > f',
      '\techo \$x # pas un commentaire',
      '\tEOF',
      'echo "début',
      'suite \$y fin" après',
    ], HighlightLanguage.shell);
    expect(s, contains('1:operator:<<-"EOF"'));
    expect(s, contains('2:string:\techo \$x # pas un commentaire'));
    expect(s, contains('3:operator:\tEOF'));
    expect(s, contains('4:string:"début'));
    expect(s, contains('5:string:suite '));
    expect(s, contains('5:variable:\$y'));
    expect(s, contains('5:string: fin"'));
  });

  test('Python : mots-clés, def, décorateur, chaînes triples', () {
    final s = show([
      '#!/usr/bin/env python3',
      '"""Doc',
      'suite."""',
      '@dataclass',
      'def main(x=3):  # c',
      '    return len(f"{x}") or None',
    ], HighlightLanguage.python);
    expect(s, contains('2:string:"""Doc'));
    expect(s, contains('3:string:suite."""'));
    expect(s, contains('4:function:@dataclass'));
    expect(s, contains('5:keyword:def'));
    expect(s, contains('5:function:main'));
    expect(s, contains('5:number:3'));
    expect(s, contains('5:comment:# c'));
    expect(s, contains('6:builtin:len'));
    expect(s, contains('6:string:f"{x}"'));
    expect(s, contains('6:keyword:None'));
  });

  test('fichiers hôtes : YAML, Dockerfile, Makefile', () {
    expect(
        show([
          'jobs:  # c',
          '  - run: echo "\${{ github.sha }}"',
          '    enabled: true',
          '    script: |',
        ], HighlightLanguage.yaml),
        containsAll([
          '1:key:jobs',
          '1:comment:# c',
          '2:key:run',
          '2:string:"\${{ github.sha }}"',
          '3:number:true',
          '4:operator:|',
        ]));
    expect(
        show([
          'FROM debian',
          'RUN apt-get update && \\',
          '    echo \$HOME',
        ], HighlightLanguage.dockerfile),
        containsAll([
          '1:key:FROM',
          '2:key:RUN',
          '2:operator:&&',
          '3:variable:\$HOME',
        ]));
    expect(
        show([
          'CC := gcc',
          'all: build # c',
          '\t@echo \$(CC) \$\$HOME',
          'ifeq (\$(X),1)',
        ], HighlightLanguage.makefile),
        containsAll([
          '1:variable:CC',
          '2:function:all',
          '2:comment:# c',
          '3:builtin:echo',
          '4:keyword:ifeq',
          '4:variable:\$(X)',
        ]));
  });

  test('langage d\'un script', () {
    ScriptInfo s(String path, String c) => ScriptInfo.fromContent(path, c);
    expect(HighlightLanguage.of(s('a.sh', 'echo\n')), HighlightLanguage.shell);
    expect(HighlightLanguage.of(s('a.py', 'x=1\n')), HighlightLanguage.python);
    expect(HighlightLanguage.of(s('/r/Dockerfile', 'RUN ls\n')),
        HighlightLanguage.dockerfile);
    expect(HighlightLanguage.of(s('/r/Makefile', 'a:\n\tls\n')),
        HighlightLanguage.makefile);
    expect(HighlightLanguage.of(s('/r/.gitlab-ci.yml', 'a:\n  script: ls\n')),
        HighlightLanguage.yaml);
  });
}
