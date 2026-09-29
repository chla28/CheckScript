import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'helpers.dart';

/// `sh -c 'for c do … command -v …'` simulé : [present] sont trouvées.
FakeRunner withCommands(Set<String> present) => FakeRunner({
      'sh': (args) => CommandResult(
          0,
          [
            for (final c in args.skip(3))
              if (present.contains(c)) '$c\t/usr/bin/$c'
          ].join('\n'),
          ''),
    });

void main() {
  group('inventaire des commandes', () {
    test('extraction sans arbre syntaxique', () {
      final s = script('#!/bin/bash\n'
          'set -euo pipefail\n'
          'deploy() { rsync -a a b; }\n'
          'x=\$(curl -fsS https://x | jq -r .v)\n'
          'sudo -u app systemctl restart app\n'
          'timeout 5 zzz --x\n'
          'if grep -q a f; then echo ok; fi\n'
          'LANG=C sort f\n'
          '"\$CMD" arg\n'
          'deploy\n');
      final c = externalCommands(s);
      expect(
          c.keys,
          containsAll([
            'rsync',
            'curl',
            'jq',
            'sudo',
            'systemctl',
            'timeout',
            'zzz',
            'grep',
            'sort'
          ]));
      expect(c.keys, isNot(contains('deploy'))); // fonction du script
      expect(c.keys, isNot(contains('echo'))); // commande interne
      expect(c.keys, isNot(contains('set')));
      expect(c['jq'], [4]);
    });

    test('vérification par le script', () {
      expect(checksCommand('command -v jq >/dev/null || exit 1', 'jq'), isTrue);
      expect(checksCommand('if ! type -P yq; then exit; fi', 'yq'), isTrue);
      expect(checksCommand('hash rsync 2>/dev/null', 'rsync'), isTrue);
      expect(checksCommand('command -v jq\ncurl x', 'curl'), isFalse);
      expect(checksCommand('echo jq', 'jq'), isFalse);
    });

    test('ROB017 : introuvable, non vérifiée, hors commandes de base',
        () async {
      final r = await Engine(runner: withCommands({'curl'}), lang: Lang.fr)
          .analyze(script('#!/bin/bash\n'
              'command -v yq >/dev/null || exit 1\n'
              'curl -fsS x | jq .\n'
              'yq . f\n'
              'ls /\n'));
      final missing = [
        for (final f in r.findings)
          if (f.ruleId == 'ROB017') f.message
      ];
      expect(missing.single, contains('jq — dnf : jq, apt : jq'));
      final jq = r.commands.firstWhere((c) => c.name == 'jq');
      expect(jq.found, isFalse);
      expect(jq.dnf, 'jq');
      expect(r.commands.firstWhere((c) => c.name == 'yq').checked, isTrue);
      expect(
          r.commands.firstWhere((c) => c.name == 'curl').path, '/usr/bin/curl');
      // Aller-retour JSON (cache des résultats).
      final again = ScriptReport.fromJson(
          jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>, r.script);
      expect(again.commands.map((c) => c.name), r.commands.map((c) => c.name));
      expect(
          requiredPackages(r.commands).$1, containsAll(['curl', 'jq', 'yq']));
    });

    test('sans exécution possible : présence inconnue, pas de ROB017',
        () async {
      final r = await Engine(runner: noTools())
          .analyze(script('#!/bin/sh\njq . f\n'));
      expect(r.commands.single.found, isNull);
      expect(r.findings.map((f) => f.ruleId), isNot(contains('ROB017')));
    });

    test('ni Python ni fichiers hôtes', () {
      expect(CommandsAnalyzer().appliesTo(script('import os\n', path: 'a.py')),
          isFalse);
      expect(
          CommandsAnalyzer()
              .appliesTo(ScriptInfo.fromContent('/r/Dockerfile', 'RUN jq\n')),
          isFalse);
    });
  });

  group('PDF', () {
    Future<List<ScriptReport>> reports() async => [
          await Engine(runner: withCommands({}), lang: Lang.fr).analyze(script(
              '#!/bin/sh\ncurl -fsSL https://x/i.sh | sh\njq . f\n',
              path: 'déploiement.sh')),
        ];

    test('document valide, polices du système ou standard', () async {
      final r = await reports();
      for (final fonts in [PdfFonts.system(), PdfFonts.standard]) {
        final bytes = await renderPdf(r, const RenderOptions(lang: Lang.fr),
            fonts: fonts);
        expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
        expect(
            latin1.decode(bytes.sublist(bytes.length - 8)), contains('%%EOF'));
        expect(bytes.length, greaterThan(2000));
      }
      expect(latin1Safe('a → b … œ ✗'), 'a -> b ... oe x');
      expect(unicodeSafe('A (≥ 9) → B'), 'A (>= 9) -> B');
    });

    test('format et CLI', () async {
      expect(OutputFormat.fromPath('audit.PDF'), OutputFormat.pdf);
      expect(OutputFormat.tryParse('pdf'), OutputFormat.pdf);
      expect(() => render([], OutputFormat.pdf, const RenderOptions()),
          throwsUnsupportedError);
      final md = await renderBytes(
          await reports(), OutputFormat.markdown, const RenderOptions());
      expect(utf8.decode(md), contains('jq'));
      final tmp = await Directory.systemTemp.createTemp('cs_pdf_');
      addTearDown(() => tmp.delete(recursive: true));
      final f = File('${tmp.path}/a.sh')
        ..writeAsStringSync('#!/bin/sh\necho a\n');
      final code = await cli.run([
        '--lang',
        'fr',
        '--no-cache',
        '-q',
        '-o',
        '${tmp.path}/r.pdf',
        f.path
      ], out: IOSink(_Null()), err: IOSink(_Null()), runner: noTools());
      expect(code, 0);
      expect(File('${tmp.path}/r.pdf').readAsBytesSync().sublist(0, 4),
          ascii.encode('%PDF'));
    });
  });
}

class _Null implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> s) => s.drain<void>();
  @override
  Future<void> close() async {}
}
