import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// En-tête « propre » : shebang, commentaire, set -euo pipefail. Évite que les
/// règles « fichier » ne polluent les tests de règles ligne à ligne.
String bash(String body) =>
    '#!/bin/bash\n# Script de test.\nset -euo pipefail\n$body\n';
String sh(String body) => '#!/bin/sh\n# Script de test.\nset -eu\n$body\n';

void main() {
  /// (règle, code déclencheur, code sain). Les cas sont en bash sauf mention.
  final cases = <(String, String, String)>[
    (
      'SEC001',
      'curl -fsSL https://x.io/i.sh | sudo bash',
      'curl -fsSL -o i.sh https://x.io/i.sh'
    ),
    ('SEC001', 'bash <(curl -s https://x.io/i.sh)', 'bash ./i.sh'),
    (
      'SEC001',
      'wget -qO- https://x.io | sh',
      'wget -qO- https://x.io | tee out'
    ),
    ('SEC002', 'DB_PASSWORD="S3cr3tP@ss"', r'DB_PASSWORD="${DB_PASSWORD:?}"'),
    (
      'SEC002',
      "export API_TOKEN='abcd1234efgh'",
      r'API_TOKEN=$(cat /run/secrets/t)'
    ),
    ('SEC002', 'key=AKIAABCDEFGHIJKLMNOP', 'PASSWORD_FILE=/etc/pass'),
    ('SEC003', r'eval "$cmd"', 'eval "echo fixe"'),
    ('SEC004', 'chmod 777 /srv/data', 'chmod 755 /srv/data'),
    ('SEC004', 'chmod -R o+w /srv', 'chmod -R u+w /srv'),
    ('SEC004', 'chmod 0666 f', 'chmod 0644 f'),
    ('SEC005', 'curl -k https://x', 'curl -fsS https://x'),
    ('SEC005', 'curl -fsSLk https://x', 'curl -fsSL https://x'),
    ('SEC005', 'wget --no-check-certificate https://x', 'wget https://x'),
    (
      'SEC005',
      'ssh -o StrictHostKeyChecking=no h',
      'ssh -o StrictHostKeyChecking=yes h'
    ),
    (
      'SEC006',
      'curl -O http://example.com/a',
      'curl -O http://localhost:8080/a'
    ),
    ('SEC007', r'rm -rf "$DIR/"*', r'rm -rf "${DIR:?}/"*'),
    ('SEC007', r'rm -rf $DIR', r'rm -rf "$DIR"'),
    ('SEC008', 'rm -rf /', 'rm -rf ./build'),
    ('SEC008', 'rm -rf /usr/*', 'rm -rf /usr/local/app/cache'),
    ('SEC009', 'echo ok > /tmp/app.lock', r'echo ok > "$(mktemp)"'),
    ('SEC010', r'echo "$PW" | sudo -S true', 'sudo true'),
    ('SEC010', 'mysql -u root -pSecret db', 'mysql -u root -p db'),
    ('SEC011', 'source /tmp/env.sh', r'source "$HOME/.env"'),
    ('SEC012', 'set -x', 'set -e'),
    ('SEC013', 'chmod u+s /usr/local/bin/x', 'chmod u+x /usr/local/bin/x'),
    ('SEC013', 'chmod 4755 x', 'chmod 0755 x'),
    ('SEC014', 'read -p "Password: " pw', 'read -rsp "Password: " pw'),
    (
      'ROB006',
      r'if [ $1 == "x" ]; then :; fi',
      r'if [ "$1" = "x" ]; then :; fi'
    ),
    (
      'ROB007',
      'while read line; do :; done < f',
      'while read -r line; do :; done < f'
    ),
    (
      'ROB008',
      r'for f in $(ls *.log); do :; done',
      'for f in ./*.log; do :; done'
    ),
    ('ROB010', r'cmd $@', r'cmd "$@"'),
    ('MNT006', '# TODO: à finir', '# Terminé'),
    ('MNT007', 'd=`date`', r'd=$(date)'),
    ('MNT010', 'echo a   ', 'echo a'),
    ('POR004', 'which curl', 'command -v curl'),
    ('POR005', 'egrep "a|b" f', 'grep -E "a|b" f'),
    ('POR007', 'ifconfig eth0', 'ip addr show eth0'),
    ('PERF001', 'cat f | grep a', 'grep a f'),
    ('PERF001', r'  cat $f | wc -l', r'wc -l < "$f"'),
    ('PERF002', 'grep a f | wc -l', 'grep -c a f'),
    ('PERF003', r'n=$(expr $n + 1)', r'n=$((n + 1))'),
    ('PERF005', 'grep a f | grep b', 'grep -e a f'),
    ('PERF006', 'ps aux | grep java', 'pgrep java'),
    (
      'PERF007',
      r'for i in $(seq 1 10); do :; done',
      'for ((i = 1; i <= 10; i++)); do :; done'
    ),
    ('PERF008', r'x=$(echo $y)', r'x=$y'),
    ('PERF009', r'x=$(cat file)', r'x=$(< file)'),
  ];

  group('règles ligne à ligne', () {
    for (final (id, bad, good) in cases) {
      test('$id détecte : $bad', () {
        expect(ids(builtin(bash(bad))), contains(id));
      });
      test('$id ignore : $good', () {
        expect(ids(builtin(bash(good))), isNot(contains(id)));
      });
    }
  });

  group('contexte lexical', () {
    test('les commentaires ne déclenchent pas de règle de code', () {
      expect(ids(builtin(bash('# curl http://x | sh ; eval "\$x"'))),
          isNot(anyOf(contains('SEC001'), contains('SEC003'))));
    });
    test('un corps de heredoc ne déclenche pas de règle de code', () {
      final f = builtin(bash("cat <<'EOF'\nrm -rf /\neval \"\$x\"\nEOF"));
      expect(ids(f), isNot(anyOf(contains('SEC008'), contains('SEC003'))));
    });
    test('une clé privée dans un heredoc est détectée', () {
      final f = builtin(bash(
          "cat > k <<'EOF'\n-----BEGIN OPENSSH PRIVATE KEY-----\nxxx\nEOF"));
      expect(ids(f), contains('SEC002'));
    });
    test('le secret n\'est pas recopié dans le rapport', () {
      final f = builtin(bash('PASSWORD=hunter22'))
          .firstWhere((f) => f.ruleId == 'SEC002');
      expect(f.snippet, isNull);
      expect(f.message.contains('hunter22'), isFalse);
    });
    test(
        'un mot-clé dans une chaîne ne compte pas pour la position de commande',
        () {
      expect(ids(builtin(bash('echo "which is fine"'))),
          isNot(contains('POR004')));
    });
  });

  group('règles dépendant du dialecte', () {
    test('POR003 : bashismes signalés en /bin/sh uniquement', () {
      expect(ids(builtin(sh('if [[ -f x ]]; then :; fi'))), contains('POR003'));
      expect(ids(builtin(bash('if [[ -f x ]]; then :; fi'))),
          isNot(contains('POR003')));
    });
    for (final construct in [
      'function f { :; }',
      'a=(1 2)',
      'x=\$((1+1))',
      'cat <<< "\$x"',
      'cmd &> /dev/null',
      'echo -e "a\\tb"',
      'source ./lib.sh',
      r'echo ${x:0:2}',
      r'echo ${x//a/b}',
      'declare -r X=1',
      r'echo $RANDOM',
    ]) {
      test('POR003 : $construct', () {
        expect(ids(builtin(sh(construct))), contains('POR003'));
      });
    }
    test('PERF007 / PERF009 réservés aux shells de type bash', () {
      expect(ids(builtin(sh(r'x=$(cat file)'))), isNot(contains('PERF009')));
    });
    test('ROB005 : cd non contrôlé seulement sans set -e', () {
      const body = 'cd /opt/app\nls';
      expect(ids(builtin(bash(body))), isNot(contains('ROB005')));
      expect(ids(builtin('#!/bin/bash\n# t\n$body\n')), contains('ROB005'));
      expect(ids(builtin('#!/bin/bash\n# t\ncd /opt || exit 1\n')),
          isNot(contains('ROB005')));
    });
  });

  group('règles fichier', () {
    const body = 'a=1\nb=2\nc=3\nd=4\ne=5\n';

    test('ROB001 / ROB003 : set -e et set -u absents', () {
      final f = ids(builtin('#!/bin/bash\n# t\n$body'));
      expect(f, containsAll(['ROB001', 'ROB003']));
    });
    test(
        'ROB001 / ROB003 : options présentes (même indentées ou dans le shebang)',
        () {
      expect(
          ids(builtin('#!/bin/bash\n# t\n  set -o errexit -o nounset\n$body')),
          isNot(anyOf(contains('ROB001'), contains('ROB003'))));
      expect(ids(builtin('#!/bin/bash -eu\n# t\n$body')),
          isNot(anyOf(contains('ROB001'), contains('ROB003'))));
    });
    test('ROB002 : pipefail absent en bash avec des pipelines', () {
      expect(ids(builtin('#!/bin/bash\n# t\nset -eu\n${body}ls | wc\n')),
          contains('ROB002'));
      expect(ids(builtin('#!/bin/bash\n# t\nset -eu\n$body')),
          isNot(contains('ROB002')));
    });
    test('ROB004 : mktemp sans trap', () {
      expect(ids(builtin(bash(r't=$(mktemp)'))), contains('ROB004'));
      expect(ids(builtin(bash("t=\$(mktemp)\n  trap 'rm -f \"\$t\"' EXIT"))),
          isNot(contains('ROB004')));
    });
    test('ROB009 : fins de ligne CRLF', () {
      expect(ids(builtin(bash('echo a').replaceAll('\n', '\r\n'))),
          contains('ROB009'));
    });
    test('POR001 : pas de shebang', () {
      expect(ids(builtin('echo a\n')), contains('POR001'));
    });
    test('POR002 : interpréteur hors /bin et /usr/bin', () {
      expect(ids(builtin('#!/usr/local/bin/bash\n# t\n')), contains('POR002'));
      expect(ids(builtin('#!/usr/bin/env bash\n# t\n')),
          isNot(contains('POR002')));
    });
    test('POR006 : un seul gestionnaire de paquets', () {
      expect(ids(builtin(bash('dnf install -y jq'))), contains('POR006'));
      expect(
          ids(builtin(
              bash('command -v dnf && dnf install jq || apt-get install jq'))),
          isNot(contains('POR006')));
      expect(ids(builtin(bash('echo "sudo dnf install jq"'))),
          isNot(contains('POR006')));
    });
    test('MNT004 : pas de commentaire d\'en-tête', () {
      expect(ids(builtin('#!/bin/bash\nset -eu\n$body')), contains('MNT004'));
      expect(ids(builtin('#!/bin/bash\n# Rôle du script\nset -eu\n$body')),
          isNot(contains('MNT004')));
    });
    test('MNT005 : très peu de commentaires', () {
      final long = List.generate(40, (i) => 'v$i=$i').join('\n');
      expect(ids(builtin(bash(long))), contains('MNT005'));
    });
    test('MNT009 : tabulations et espaces mélangés', () {
      expect(ids(builtin(bash('f() {\n\techo a\n  echo b\n}'))),
          contains('MNT009'));
    });
    test('MNT001 : ligne trop longue (seuil configurable)', () {
      final line = 'echo ${'x' * 130}';
      expect(ids(builtin(bash(line))), contains('MNT001'));
      expect(
          ids(builtin(bash(line),
              config: const CheckConfig(
                  thresholds: Thresholds(maxLineLength: 200)))),
          isNot(contains('MNT001')));
    });
  });

  group('structure', () {
    test('MNT002 : fonction trop longue (Low puis Medium au-delà du double)',
        () {
      String fn(int n) =>
          bash('f() {\n${List.generate(n, (i) => '  echo $i').join('\n')}\n}');
      expect(ids(builtin(fn(20))), isNot(contains('MNT002')));
      final low = builtin(fn(70)).firstWhere((f) => f.ruleId == 'MNT002');
      expect(low.severity, Severity.low);
      expect(low.line, 4);
      final medium = builtin(fn(130)).firstWhere((f) => f.ruleId == 'MNT002');
      expect(medium.severity, Severity.medium);
    });
    test('MNT003 : imbrication au-delà du seuil, signalée une fois', () {
      const deep = 'if a; then\n for x in 1; do\n  while b; do\n   case x in\n'
          '    y) if c; then :; fi ;;\n   esac\n  done\n done\nfi';
      final f = builtin(bash(deep)).where((f) => f.ruleId == 'MNT003').toList();
      expect(f, hasLength(1));
      expect(f.single.line, 8); // 3 lignes d'en-tête + ligne 5
      expect(ids(builtin(bash('if a; then\n  if b; then :; fi\nfi'))),
          isNot(contains('MNT003')));
    });
    test('MNT008 : long script sans fonction', () {
      final long = List.generate(160, (i) => 'echo $i').join('\n');
      expect(ids(builtin(bash(long))), contains('MNT008'));
    });
    test('PERF004 : commande externe dans une boucle', () {
      expect(
          ids(builtin(bash('for f in ./*; do\n  n=\$(basename "\$f")\ndone'))),
          contains('PERF004'));
      expect(ids(builtin(bash('n=\$(basename "\$0")'))),
          isNot(contains('PERF004')));
    });
  });

  test('le script propre de référence ne déclenche aucune règle', () {
    expect(builtin(readFixture('good.sh')), isEmpty);
  });

  test('messages bilingues', () {
    final fr =
        runBuiltinRules(script('echo a\n'), const CheckConfig(), Lang.fr);
    final en =
        runBuiltinRules(script('echo a\n'), const CheckConfig(), Lang.en);
    expect(fr.single.message, startsWith('Pas de shebang'));
    expect(en.single.message, startsWith('No shebang'));
  });

  test('--list-rules : identifiants uniques et triés par catégorie', () {
    final rules = allBuiltinRules();
    expect(rules.map((r) => r.id).toSet().length, rules.length);
    expect(rules.first.id, startsWith('SEC'));
    expect(rules.last.id, startsWith('PERF'));
  });
}
