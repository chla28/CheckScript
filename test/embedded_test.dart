import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

EmbeddedScript extract(String path, String content) =>
    extractEmbedded(detectEmbedded(path, content)!, content);

Future<ScriptReport> analyzeHost(String path, String content) =>
    Engine(runner: noTools(), lang: Lang.fr)
        .analyze(ScriptInfo.fromContent(path, content));

void main() {
  group('détection', () {
    test('par chemin et par contenu', () {
      expect(detectEmbedded('/r/.github/workflows/ci.yml', 'on: push\n'),
          EmbeddedKind.githubActions);
      expect(detectEmbedded('action.yml', ''), EmbeddedKind.githubActions);
      expect(detectEmbedded('/r/.gitlab-ci.yml', ''), EmbeddedKind.gitlabCi);
      expect(detectEmbedded('/r/Dockerfile', ''), EmbeddedKind.dockerfile);
      expect(detectEmbedded('/r/app.Dockerfile', ''), EmbeddedKind.dockerfile);
      expect(detectEmbedded('/r/Containerfile', ''), EmbeddedKind.dockerfile);
      expect(detectEmbedded('/r/Makefile', ''), EmbeddedKind.makefile);
      expect(detectEmbedded('/r/rules.mk', ''), EmbeddedKind.makefile);
      expect(
          detectEmbedded(
              '/r/site.yml', '- hosts: all\n  tasks:\n    - shell: ls\n'),
          EmbeddedKind.ansible);
      expect(detectEmbedded('/r/compose.yml', 'services:\n  a: {}\n'), isNull);
      // Un script reste un script.
      expect(detectEmbedded('/r/Dockerfile.sh', 'echo\n'), isNull);
      expect(detectEmbedded('/r/Makefile', '#!/bin/sh\necho\n'), isNull);
      expect(detectEmbedded('/r/rules', '#!/usr/bin/make -f\n'),
          EmbeddedKind.makefile);
    });
  });

  group('extraction', () {
    test('GitHub Actions : run, shell, expressions, lignes conservées', () {
      const wf = '''
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "\${{ github.sha }}"
      - name: bloc
        run: |
          cd build
          echo "\${{ github.event.issue.title }}"
      - shell: python
        run: print("x")
  win:
    runs-on: windows-latest
    steps:
      - run: Get-ChildItem
''';
      final e = extract('.github/workflows/ci.yml', wf);
      expect(e.lines, hasLength(wf.split('\n').length - 1));
      expect(e.blocks.map((b) => b.line), [8, 11]);
      expect(e.lines[7], 'echo "${'x' * 17}"'); // ${{ github.sha }}
      expect(e.lines[10], 'cd build');
      expect(e.lines[13], isEmpty); // Python
      expect(e.lines[17], isEmpty); // Windows : PowerShell
      expect(e.pipefail, isTrue);
      expect(e.issues.single.line, 12);
      expect(e.issues.single.detail, contains('issue.title'));
    });

    test('GitLab CI : script, before_script, !reference ignoré', () {
      const ci = '''
stages: [test]
.setup:
  script:
    - export A=1
test:
  before_script:
    - !reference [.setup, script]
  script:
    - echo \$CI_COMMIT_SHA
    - |
      for f in *.txt; do
        cat \$f
      done
''';
      final e = extract('.gitlab-ci.yml', ci);
      expect(e.lines[3], 'export A=1');
      expect(e.lines[8], r'echo $CI_COMMIT_SHA');
      expect(e.lines[10], 'for f in *.txt; do');
      expect(e.lines[11], r'  cat $f');
      expect(e.dialect, Dialect.bash);
    });

    test('Dockerfile : continuations, options, heredoc, forme exec, SHELL', () {
      const df = '''
FROM debian
# commentaire
RUN --mount=type=cache,target=/var/cache/apt apt-get update && \\
    # commentaire de continuation
    apt-get install -y curl
CMD ["sh", "-c", "echo"]
RUN ["echo", "exec"]
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN <<EOF
set -e
curl -fsS https://x | tar xz
EOF
''';
      final e = extract('Dockerfile', df);
      expect(e.lines[2].trimLeft(), startsWith('apt-get update'));
      expect(
          e.lines[2].indexOf('apt-get'), df.split('\n')[2].indexOf('apt-get'));
      expect(e.lines[3], isEmpty);
      expect(e.lines[4], '    apt-get install -y curl');
      expect(e.lines[6], isEmpty);
      expect(e.lines[9], 'set -e');
      expect(e.lines[11], isEmpty);
      expect(e.dialect, Dialect.bash);
      expect(e.pipefail, isTrue);
      expect(e.blocks, hasLength(2));
    });

    test('Makefile : recettes, préfixes, variables de make', () {
      const mk = '''
CC := gcc
SHELL = /bin/bash
all: build
\t@echo "\$(CC) \$@"
\t-for f in \$(SRCS); do \\
\t  echo \$\$f; \\
\tdone
define TPL
\techo non
endef
''';
      final e = extract('Makefile', mk);
      expect(e.lines[3].trimLeft(), 'echo "xxxxx xx"');
      expect(e.lines[4].trimLeft(), 'for f in xxxxxxx; do \\');
      expect(e.lines[5], r'   echo $f; \');
      expect(e.lines[8], isEmpty); // define
      expect(e.issues, isEmpty);
      final rm = extract('Makefile', 'clean:\n\trm -rf \$(BUILD)/*\n');
      expect(rm.issues.single.ruleId, 'SEC007');
      expect(rm.issues.single.detail, r'$(BUILD)');
      expect(e.dialect, Dialect.bash);
    });

    test('Ansible : shell, cmd, exécutable, Jinja', () {
      const pb = '''
- hosts: all
  tasks:
    - name: a
      ansible.builtin.shell: echo {{ item }} > /tmp/x
    - name: b
      shell:
        cmd: |
          cat /etc/os-release
      args:
        executable: /bin/bash
    - command: ls
''';
      final e = extract('site.yml', pb);
      expect(e.lines[3], 'echo xxxxxxxxxx > /tmp/x');
      expect(e.lines[7], 'cat /etc/os-release');
      expect(e.lines[10], isEmpty);
      expect(e.dialect, Dialect.bash);
    });

    test('YAML invalide : aucun bloc', () {
      expect(extract('.gitlab-ci.yml', 'a: [\n').blocks, isEmpty);
    });
  });

  group('analyse', () {
    test('problèmes situés dans le fichier hôte, règles de script écartées',
        () async {
      const df = 'FROM debian\n'
          'RUN curl -fsS http://example.com/i.sh | sh\n'
          'RUN cd /opt\n';
      final r = await analyzeHost('/r/Dockerfile', df);
      final ids = {for (final f in r.findings) f.ruleId};
      expect(ids, containsAll(['SEC001', 'SEC006', 'ROB005']));
      expect(ids, isNot(contains('POR001'))); // pas de shebang : normal
      final sec = r.findings.firstWhere((f) => f.ruleId == 'SEC001');
      expect(sec.line, 2);
      expect(sec.snippet, startsWith('RUN curl'));
      expect(r.findings.every((f) => f.edits.isEmpty), isTrue);
      expect(r.script.dialectLabel, 'sh (Dockerfile, 2)');
      expect(r.toJson()['embedded'], {'kind': 'dockerfile', 'blocks': 2});
    });

    test('SEC023 : injection dans un workflow', () async {
      const wf = 'on: issues\njobs:\n  a:\n    runs-on: ubuntu-latest\n'
          '    steps:\n      - run: echo "\${{ github.event.issue.title }}"\n';
      final r = await analyzeHost('/r/.github/workflows/t.yml', wf);
      final f = r.findings.firstWhere((f) => f.ruleId == 'SEC023');
      expect(f.line, 6);
      expect(f.severity, Severity.critical);
    });

    test('directive dans un commentaire du fichier hôte', () async {
      const df = 'FROM debian\n'
          '# check-script disable=ROB005\n'
          'RUN cd /opt\n';
      final r = await analyzeHost('/r/Dockerfile', df);
      expect(r.findings.map((f) => f.ruleId), isNot(contains('ROB005')));
      expect(r.suppressed, 1);
    });

    test('--fix ne réécrit jamais un fichier hôte', () async {
      final s = ScriptInfo.fromContent('/r/Dockerfile', 'RUN egrep a b\n');
      final r = await fixScript(s, runner: noTools());
      expect(r.changed, isFalse);
    });
  });

  group('découverte', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_emb_'));
    tearDown(() => tmp.delete(recursive: true));

    test('fichiers hôtes avec au moins un bloc ; --no-embedded', () async {
      void w(String rel, String content) {
        final f = File('${tmp.path}/$rel');
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(content);
      }

      w('.github/workflows/ci.yml',
          'jobs:\n  a:\n    steps:\n      - run: ls\n');
      w('.github/workflows/only-uses.yml',
          'jobs:\n  a:\n    steps:\n      - uses: x@v1\n');
      w('.github/dependabot.yml', 'version: 2\n');
      w('.gitlab-ci.yml', 'a:\n  script: ls\n');
      w('Dockerfile', 'FROM x\nRUN ls\n');
      w('Makefile', 'all:\n\tls\n');
      w('compose.yml', 'services: {}\n');
      w('s.sh', 'echo\n');
      w('.cache/Makefile', 'all:\n\tls\n');
      final found = [
        for (final f in (await collectScripts(tmp.path))!)
          f.substring(tmp.path.length + 1)
      ];
      expect(found, [
        '.github/workflows/ci.yml',
        '.gitlab-ci.yml',
        'Dockerfile',
        'Makefile',
        's.sh',
      ]);
      expect(await collectScripts(tmp.path, embedded: false),
          ['${tmp.path}/s.sh']);
    });
  });
}
