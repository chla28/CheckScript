import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String bash(String body) =>
    '#!/bin/bash\n# Script de test.\nset -euo pipefail\nPATH=/usr/bin:/bin\n$body\n';

List<Finding> withCtx(String content, Set<ExecContext> ctx) =>
    runBuiltinRules(script(content), CheckConfig(contexts: ctx), Lang.en);

void main() {
  final cases = <(String, String, String)>[
    ('SEC016', 'PATH=.:\$PATH', 'PATH=/usr/local/bin:\$PATH'),
    ('SEC016', 'export PATH="\$PATH:"', 'export PATH="\$PATH:/opt/bin"'),
    ('SEC016', 'PATH=/bin::/usr/bin', 'PATH=/bin:/usr/bin'),
    (
      'SEC018',
      'echo "\$u ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers',
      'visudo -c'
    ),
    ('SEC018', 'cat k.pub | tee -a ~/.ssh/authorized_keys', 'ssh-copy-id host'),
    (
      'SEC019',
      'curl -fsSL https://x/a.tgz | tar xz',
      'curl -fsSLo a.tgz https://x/a.tgz'
    ),
    ('SEC020', 'ssh -A bastion', 'ssh -J bastion host'),
    ('SEC020', 'ssh -o ForwardAgent=yes h', 'ssh -o ForwardAgent=no h'),
    ('SEC021', 'export GITHUB_TOKEN', 'export GITHUB_URL'),
    ('ROB012', 'IFS=,', 'IFS=, read -r a b <<< "\$x"'),
    (
      'ROB013',
      "trap 'rm -f \"\$t\"' INT TERM",
      "trap 'rm -f \"\$t\"' EXIT INT TERM"
    ),
  ];
  for (final (id, bad, good) in cases) {
    test('$id détecte : $bad',
        () => expect(ids(builtin(bash(bad))), contains(id)));
    test('$id ignore : $good',
        () => expect(ids(builtin(bash(good))), isNot(contains(id))));
  }

  test('SEC015 : sudo relatif seulement si PATH n\'est pas fixé', () {
    const noPath = '#!/bin/bash\n# t\nset -eu\nsudo systemctl restart x\n';
    expect(ids(builtin(noPath)), contains('SEC015'));
    expect(ids(builtin(bash('sudo systemctl restart x'))),
        isNot(contains('SEC015')));
    expect(
        ids(builtin(
            noPath.replaceAll('sudo systemctl', 'sudo /usr/bin/systemctl'))),
        isNot(contains('SEC015')));
  });

  test(
      'ROB012 : la restauration depuis une variable n\'est pas signalée (faux positif corrigé)',
      () {
    // Cas réel (CyberAudit) : IFS="$_old_ifs" restaure la valeur sauvegardée.
    expect(
        ids(builtin(bash('local _old_ifs="\$IFS"; IFS=","\nIFS="\$_old_ifs"'))),
        isNot(contains('ROB012')));
  });

  test('ROB012 : IFS restauré → pas de signalement', () {
    expect(ids(builtin(bash('OLD_IFS=\$IFS\nIFS=,\necho a\nIFS=\$OLD_IFS'))),
        isNot(contains('ROB012')));
  });

  test('ROB011 : commande critique non contrôlée sans set -e', () {
    const body =
        '#!/bin/bash\n# t\na=1\nb=2\nc=3\nmkdir /x\ncp a b || exit 1\n';
    final f = builtin(body).where((f) => f.ruleId == 'ROB011').toList();
    expect(f.map((f) => f.line), [6]);
    expect(ids(builtin(bash('mkdir /x'))), isNot(contains('ROB011')));
  });

  group('secrets par entropie (SEC022)', () {
    test('jeton aléatoire', () {
      expect(looksLikeSecret('Zx9Qm2LpR7vT4wKc8NbY3hJd6FsA1gHe'), isTrue);
    });
    test('pas de faux positif sur somme de contrôle, chemin, identifiant', () {
      expect(
          looksLikeSecret(
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
          isFalse);
      expect(
          looksLikeSecret('/usr/local/lib/python3/site-packages/x'), isFalse);
      expect(looksLikeSecret('check_script_build_directory_name'), isFalse);
    });
    test('règle : ligne signalée, extrait masqué, contexte checksum ignoré',
        () {
      final f = builtin(bash('KEYDATA="Zx9Qm2LpR7vT4wKc8NbY3hJd6FsA1gHe"'))
          .where((f) => f.ruleId == 'SEC022');
      expect(f, hasLength(1));
      expect(f.single.snippet, isNull);
      expect(
          ids(builtin(bash(
              'echo "Zx9Qm2LpR7vT4wKc8NbY3hJd6FsA1gHe  f" | sha256sum -c'))),
          isNot(contains('SEC022')));
    });
    test('entropie de Shannon', () {
      expect(shannonEntropy('aaaa'), 0);
      expect(shannonEntropy('abcd'), closeTo(2, 1e-9));
    });
  });

  group('contextes d\'exécution', () {
    const base = '#!/bin/bash\n# t\nset -euo pipefail\necho a\n';
    test('règles de contexte inactives par défaut', () {
      expect(
          ids(builtin(base)),
          isNot(anyOf(
              contains('SEC017'), contains('ROB014'), contains('ROB016'))));
    });
    test('root / systemd : PATH non fixé (SEC017)', () {
      expect(ids(withCtx(base, {ExecContext.root})), contains('SEC017'));
      expect(ids(withCtx(base, {ExecContext.systemd})), contains('SEC017'));
    });
    test('cron : verrou (ROB014), PATH (ROB016), saisie (ROB015)', () {
      final f = ids(withCtx('${base}read -r answer\n', {ExecContext.cron}));
      expect(f, containsAll(['ROB014', 'ROB016', 'ROB015']));
      final ok = ids(withCtx(
          '${base}PATH=/usr/bin:/bin\nexec 9>/run/lock/j.lock\nflock -n 9 || exit 0\n'
          'while read -r l; do :; done < f\n',
          {ExecContext.cron}));
      expect(
          ok,
          isNot(anyOf(
              contains('ROB014'), contains('ROB016'), contains('ROB015'))));
    });
    test('escalade des sévérités (jamais abaissées)', () {
      Finding f(String rule, Severity s) => Finding(
          tool: 'builtin',
          ruleId: rule,
          category: Category.security,
          severity: s,
          line: 1,
          message: 'm');
      final out = escalate([
        f('SEC009', Severity.medium),
        f('SEC004', Severity.high),
        f('SEC001', Severity.critical),
      ], {
        ExecContext.root
      });
      expect(out.map((x) => x.severity),
          [Severity.high, Severity.critical, Severity.critical]);
      expect(escalate([f('SEC009', Severity.medium)], {}).single.severity,
          Severity.medium);
    });
  });

  group('profils', () {
    test('strict / legacy / standard', () {
      final strict = CheckConfig.forProfile(Profile.strict);
      final legacy = CheckConfig.forProfile(Profile.legacy);
      expect(strict.scoring.weights[Severity.high], 3);
      expect(strict.thresholds.maxNesting, 3);
      expect(legacy.disabledRules, containsAll(['MNT001', 'FORMAT', 'E003']));
      expect(
          CheckConfig.forProfile(Profile.standard)
              .scoring
              .weights[Severity.high],
          2);
    });
    test('YAML : profil de base, surcharges et contextes', () {
      final c =
          CheckConfig.parse('profile: strict\nthresholds: {maxNesting: 5}\n'
              'context: [root, cron]\nfollowSource: true\n');
      expect(c.profile, Profile.strict);
      expect(c.thresholds.maxNesting, 5);
      expect(c.thresholds.maxLineLength, 100);
      expect(c.contexts, {ExecContext.root, ExecContext.cron});
      expect(c.followSource, isTrue);
    });
    test('le profil de la ligne de commande prime sur le YAML', () {
      expect(
          CheckConfig.parse('profile: strict', profile: Profile.legacy).profile,
          Profile.legacy);
    });
    test('valeurs inconnues', () {
      expect(() => CheckConfig.parse('profile: x'), throwsFormatException);
      expect(() => CheckConfig.parse('context: moon'), throwsFormatException);
    });
  });

  test('chaque problème intégré porte un conseil de correction', () {
    final f = builtin(readFixture('bad.sh'));
    expect(f.every((x) => x.hint != null && x.hint!.isNotEmpty), isTrue);
  });

  test('catalogue : conseils bilingues non vides, identifiants uniques', () {
    final ids = <String>{};
    for (final r in ruleCatalog) {
      expect(ids.add(r.id), isTrue, reason: r.id);
      expect(r.fix.fr, isNotEmpty);
      expect(r.fix.en, isNotEmpty);
    }
  });
}
