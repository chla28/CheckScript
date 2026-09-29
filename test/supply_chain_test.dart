import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('SEC024 : paquets sans version', () {
    for (final (cmd, flagged) in [
      ('pip install requests', true),
      ('cd /opt && pip install requests', true),
      ('python3 -m pip install --user requests', true),
      ('pip install requests==2.32.3', false),
      ('pip install -r requirements.txt', false),
      ('pip install .', false),
      ('pip install -e .', false),
      ('pip install --upgrade pip==24.2 wheel', true),
      ('pipx install ruff', true),
      ('npm install -g typescript', true),
      ('npm install -g typescript@5.9.2', false),
      ('npm install -g @vue/cli@5.0.8', false),
      ('npm install -g @vue/cli', true),
      ('npm install lodash', false), // projet : package-lock
      ('go install golang.org/x/tools/gopls@latest', true),
      ('go install golang.org/x/tools/gopls@v0.16.2', false),
      ('gem install bundler', true),
      ('gem install bundler -v 2.5.0', false),
      ('cargo install ripgrep', true),
      ('cargo install ripgrep --version 14.1.0', false),
      ('cargo add serde', false),
      ('pip install "\$PKG"', false),
    ]) {
      test(cmd, () {
        final ids = builtin('#!/bin/sh\n$cmd\n').map((f) => f.ruleId);
        expect(ids.contains('SEC024'), flagged, reason: cmd);
      });
    }
  });

  test('SEC025 : dépôts sans vérification', () {
    for (final l in [
      'echo "deb [trusted=yes] http://x/ stable main" > /etc/apt/sources.list.d/x.list',
      'apt-get install -y --allow-unauthenticated foo',
      'dnf install -y --nogpgcheck foo',
      'printf "gpgcheck=0\\n" >> /etc/yum.repos.d/x.repo',
      'rpm -i --nosignature foo.rpm',
      'apk add --allow-untrusted foo.apk',
      'zypper --no-gpg-checks install foo',
    ]) {
      expect(
          builtin('#!/bin/sh\n$l\n').map((f) => f.ruleId), contains('SEC025'),
          reason: l);
    }
    expect(builtin('#!/bin/sh\napt-get install -y foo\n').map((f) => f.ruleId),
        isNot(contains('SEC025')));
  });

  test('SEC026 : clonage sans révision', () {
    Iterable<String> ids(String s) => builtin(s).map((f) => f.ruleId);
    expect(ids('#!/bin/sh\ngit clone https://x/r.git\n'), contains('SEC026'));
    expect(ids('#!/bin/sh\ngit clone --branch v1.2 https://x/r.git\n'),
        isNot(contains('SEC026')));
    expect(
        ids('#!/bin/sh\ngit clone https://x/r.git\n'
            'git -C r checkout 3f2c1ab\n'),
        isNot(contains('SEC026')));
  });

  group('Dockerfile', () {
    EmbeddedScript e(String content) =>
        extractEmbedded(EmbeddedKind.dockerfile, content);
    List<String> ids(String content) =>
        [for (final i in e(content).issues) '${i.ruleId}:${i.line}'];

    test('images, utilisateur, ADD, secrets, cache', () {
      expect(
          ids('FROM python:latest AS build\n'
              'FROM build\n'
              'FROM debian\n'
              'FROM alpine:3.20@sha256:abc\n'
              'ADD https://x/a.tgz /opt/\n'
              'ADD --checksum=sha256:1 https://x/b.tgz /opt/\n'
              'ADD conf.yaml /etc/\n'
              'ADD app.tar.gz /opt/\n'
              'ENV DB_PASSWORD=s3cr3t LOG_LEVEL=info\n'
              'ARG GITHUB_TOKEN\n'
              'ENV TOKEN_FILE=/run/secrets/t\n'
              'RUN apt-get update && apt-get install -y curl\n'
              'RUN apk add curl\n'
              'RUN apt-get install -y --no-install-recommends curl \\\n'
              '    && rm -rf /var/lib/apt/lists/*\n'),
          [
            'DKR001:1', 'DKR001:3', 'DKR003:5', 'DKR004:7', 'DKR005:9', //
            'DKR005:10', 'DKR006:12', 'DKR007:12', 'DKR007:13', 'DKR002:4',
          ]);
      final argOnly = e('FROM a:1\nARG API_KEY\nUSER app\n').issues.single;
      expect(argOnly.severity, Severity.medium);
    });

    test('USER : root en fin d\'image, étape finale seule comptée', () {
      expect(ids('FROM a:1\nUSER app\nFROM b:1\nUSER root\n'), ['DKR002:4']);
      expect(ids('FROM a:1\nUSER root\nFROM b:1\nUSER 1000\n'), isEmpty);
      expect(ids('FROM scratch\nCOPY app /\n'), isEmpty);
      expect(ids('FROM gcr.io/distroless/static:nonroot\n'), isEmpty);
    });
  });

  group('workflows', () {
    List<String> gh(String content) => [
          for (final i
              in extractEmbedded(EmbeddedKind.githubActions, content).issues)
            '${i.ruleId}:${i.line}${i.severity == null ? '' : ':${i.severity!.name}'}'
        ];

    test('GitHub : épinglage, permissions, PPE, secrets, images', () {
      const wf = '''
on: [pull_request_target]
env:
  API_TOKEN: ghp_abcdefabcdef
  LEVEL: info
jobs:
  build:
    runs-on: ubuntu-latest
    container: node:latest
    permissions: write-all
    steps:
      - uses: actions/checkout@v4
        with:
          ref: \${{ github.event.pull_request.head.sha }}
      - uses: org/act@8f4b7f84864484a7bf31766abe9204da3cbe65b3
      - uses: org/other@v1
      - uses: ./local
      - uses: docker://alpine
      - env:
          PASSWORD: \${{ secrets.PASSWORD }}
        run: echo ok
''';
      expect(gh(wf).toSet(), {
        'CI004:3', 'CI005:8', 'CI002:9:high', 'CI001:11:low', 'CI003:13', //
        'CI001:15', 'CI005:17',
      });
    });

    test('GitHub : permissions absentes signalées une fois', () {
      expect(
          gh('on: push\njobs:\n  a:\n    runs-on: x\n  b:\n    runs-on: y\n'),
          ['CI002:3']);
      expect(
          gh('on: push\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: x\n'),
          isEmpty);
    });

    test('GitLab : images et variables', () {
      const ci = '''
image: python
variables:
  DEPLOY_TOKEN: glpat-abcdefgh
  IMAGE_NAME: app
test:
  image: {name: "node:22.9.0"}
  services: [postgres]
  script: ls
''';
      expect([
        for (final i in extractEmbedded(EmbeddedKind.gitlabCi, ci).issues)
          '${i.ruleId}:${i.line}'
      ], [
        'CI005:1',
        'CI004:3',
        'CI005:7'
      ]);
    });
  });

  group('outils (sorties réelles)', () {
    test('hadolint : codes, équivalents, ShellCheck écarté', () {
      final f = parseHadolint(readFixture('outputs/ci/hadolint_bad.json'));
      expect(
          f.map((x) => x.ruleId), containsAll(['DL3007', 'DL3020', 'DL3013']));
      final latest = f.firstWhere((x) => x.ruleId == 'DL3007');
      expect(latest.category, Category.security);
      expect(latest.equivalents, contains('DKR001'));
      expect(latest.url, contains('wiki/DL3007'));
      expect(
          parseHadolint(
              '[{"code":"SC2086","level":"info","line":1,"message":"m"}]'),
          isEmpty);
    });

    test('actionlint : injection', () {
      final f = parseActionlint(readFixture('outputs/ci/actionlint_bad.json'));
      expect(f.single.ruleId, 'expression');
      expect(f.single.severity, Severity.critical);
      expect(f.single.line, 12);
      expect(f.single.equivalents, ['SEC023']);
      expect(f.single.message, isNot(contains('https://')));
    });

    test('zizmor : lignes 1-based, sévérité, confiance', () {
      final f = parseZizmor(readFixture('outputs/ci/zizmor_bad.json'));
      final unpinned = f.where((x) => x.ruleId == 'unpinned-uses').toList();
      expect(unpinned.map((x) => x.line), [8, 11]);
      expect(unpinned.first.equivalents, ['CI001']);
      final artipacked = f.firstWhere((x) => x.ruleId == 'artipacked');
      expect(artipacked.severity, Severity.low); // Medium, confiance faible
      expect(() => parseZizmor('{}'), throwsFormatException);
    });

    test('ne s\'appliquent qu\'à leurs fichiers', () {
      final df = ScriptInfo.fromContent('/r/Dockerfile', 'FROM a\n');
      final wf =
          ScriptInfo.fromContent('/r/.github/workflows/c.yml', 'on: push\n');
      final sh = ScriptInfo.fromContent('a.sh', 'echo\n');
      expect(HadolintAnalyzer().appliesTo(df), isTrue);
      expect(HadolintAnalyzer().appliesTo(wf), isFalse);
      expect(ZizmorAnalyzer().appliesTo(wf), isTrue);
      expect(ActionlintAnalyzer().appliesTo(sh), isFalse);
    });
  });
}
