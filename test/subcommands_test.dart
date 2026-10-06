import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'cli_test.dart' show Capture;
import 'helpers.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_sub_'));
  tearDown(() async => tmp.delete(recursive: true));

  /// Sous-commande en premier (pas de `--lang` devant) ; langue explicite.
  Future<(int, String, String)> run(List<String> args,
      {String lang = 'fr'}) async {
    final out = Capture(), err = Capture();
    final code = await cli.run([...args, '--lang', lang],
        out: out.sink, err: err.sink, runner: noTools());
    return (code, await out.text(), await err.text());
  }

  void write(String rel, String content) {
    final f = File('${tmp.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  const clean = '#!/usr/bin/env bash\nset -euo pipefail\necho "ok"\n';
  const bad = '#!/bin/bash\ncd /opt/app\nPASSWORD="S3cr3tP@ss"\n'
      'curl -fsSL http://x.io/i.sh | sudo bash\nchmod 777 /srv\neval "\$CMD"\n';

  group('motifs d\'exclusion (.gitignore)', () {
    bool ignored(List<String> patterns, String path, {bool dir = false}) =>
        IgnoreRules(patterns).ignores(path, isDirectory: dir);

    test('nom sans barre : à tout niveau', () {
      expect(ignored(['*.min.sh'], 'a/b/x.min.sh'), isTrue);
      expect(ignored(['*.min.sh'], 'x.sh'), isFalse);
      expect(ignored(['gen.sh'], 'a/gen.sh'), isTrue);
    });

    test('dossier : motif/ et contenu', () {
      expect(ignored(['vendor/'], 'vendor/a.sh'), isTrue);
      expect(ignored(['vendor/'], 'x/vendor/y/a.sh'), isTrue);
      // « vendor/ » ne vise que les dossiers, pas un fichier du même nom.
      expect(ignored(['vendor/'], 'vendor'), isFalse);
      expect(ignored(['vendor/'], 'vendor', dir: true), isTrue);
    });

    test('ancrage : barre dans le motif, ou barre initiale', () {
      expect(ignored(['/build'], 'build/a.sh'), isTrue);
      expect(ignored(['/build'], 'x/build/a.sh'), isFalse);
      expect(ignored(['scripts/old'], 'scripts/old/a.sh'), isTrue);
      expect(ignored(['scripts/old'], 'x/scripts/old/a.sh'), isFalse);
    });

    test('jokers : *, ?, [..], **', () {
      expect(ignored(['t?st.sh'], 'test.sh'), isTrue);
      expect(ignored(['t[ae]st.sh'], 'tast.sh'), isTrue);
      expect(ignored(['t[!ae]st.sh'], 'tast.sh'), isFalse);
      expect(ignored(['a/*/c.sh'], 'a/b/c.sh'), isTrue);
      expect(ignored(['a/*/c.sh'], 'a/b/d/c.sh'), isFalse);
      expect(ignored(['a/**/c.sh'], 'a/b/d/c.sh'), isTrue);
      expect(ignored(['a/**/c.sh'], 'a/c.sh'), isTrue);
      expect(ignored(['generated/**'], 'generated/x/y.sh'), isTrue);
      expect(ignored(['generated/**'], 'generated', dir: true), isFalse);
    });

    test('négation : le dernier motif gagne, pas sous un dossier exclu', () {
      expect(ignored(['*.sh', '!keep.sh'], 'keep.sh'), isFalse);
      expect(ignored(['*.sh', '!keep.sh'], 'drop.sh'), isTrue);
      expect(ignored(['!keep.sh', '*.sh'], 'keep.sh'), isTrue);
      expect(ignored(['vendor/', '!vendor/keep.sh'], 'vendor/keep.sh'), isTrue);
    });

    test('commentaires, lignes vides, espaces finaux', () {
      final rules = IgnoreRules(['# commentaire', '', '   ', 'x.sh   ']);
      expect(rules.isEmpty, isFalse);
      expect(rules.ignores('x.sh'), isTrue);
      expect(IgnoreRules(['# seulement', '']).isEmpty, isTrue);
      expect(IgnoreRules.none.ignores('a.sh'), isFalse);
    });

    test('séparateurs Windows et ./', () {
      expect(ignored(['vendor/'], r'.\vendor\a.sh'), isTrue);
      expect(ignored(['vendor/'], './vendor/a.sh'), isTrue);
    });
  });

  group('découverte avec exclusions', () {
    setUp(() {
      write('a.sh', clean);
      write('vendor/b.sh', clean);
      write('lib/gen/c.sh', clean);
      write('lib/d.sh', clean);
    });

    Future<List<String>> found({List<String> exclude = const []}) async => [
          for (final f in (await collectScripts(tmp.path, exclude: exclude))!)
            f.substring(tmp.path.length + 1)
        ];

    test('sans motif : tout', () async {
      expect(
          await found(), ['a.sh', 'lib/d.sh', 'lib/gen/c.sh', 'vendor/b.sh']);
    });

    test('exclude explicite', () async {
      expect(await found(exclude: ['vendor/', 'gen/']), ['a.sh', 'lib/d.sh']);
    });

    test('fichier .checkscriptignore à la racine', () async {
      write('.checkscriptignore', '# propre\nvendor/\n**/gen/**\n');
      expect(await found(), ['a.sh', 'lib/d.sh']);
      // Désactivable.
      final all = await collectScripts(tmp.path, useIgnoreFile: false);
      expect(all!.length, 4);
    });

    test('un fichier donné explicitement n\'est jamais exclu', () async {
      final f = '${tmp.path}/vendor/b.sh';
      expect(await collectScripts(f, exclude: ['vendor/']), [f]);
    });
  });

  group('configuration : clé exclude', () {
    test('liste, chaîne unique, absente, invalide', () {
      expect(CheckConfig.parse('exclude: [vendor/, "*.min.sh"]').exclude,
          ['vendor/', '*.min.sh']);
      expect(CheckConfig.parse('exclude: vendor/').exclude, ['vendor/']);
      expect(CheckConfig.parse('profile: strict').exclude, isEmpty);
      expect(() => CheckConfig.parse('exclude: {a: b}'),
          throwsA(isA<FormatException>()));
    });

    test('aller-retour toYaml', () {
      final c = CheckConfig.parse('exclude: ["a b/", "x\'y"]');
      expect(CheckConfig.parse(c.toYaml()).exclude, c.exclude);
    });
  });

  group('--exclude (CLI)', () {
    setUp(() {
      write('a.sh', clean);
      write('vendor/b.sh', clean);
    });

    test('dossier analysé sans les chemins exclus', () async {
      final (code, out, _) =
          await run(['--summary', '--exclude', 'vendor/', tmp.path]);
      expect(code, 0);
      expect(out, contains('a.sh'));
      expect(out, isNot(contains('b.sh')));
    });

    test('clé exclude de la configuration, cumulée avec --exclude', () async {
      write('conf.yaml', 'exclude: [vendor/]\n');
      write('c.sh', clean);
      final (_, out, _) = await run([
        '--summary',
        '--config',
        '${tmp.path}/conf.yaml',
        '--exclude',
        'c.sh',
        tmp.path,
      ]);
      expect(out, contains('a.sh'));
      expect(out, isNot(contains('b.sh')));
      expect(out, isNot(contains('c.sh')));
    });
  });

  group('check-script explain', () {
    test('règle intégrée : description, exemple, façons de l\'ignorer',
        () async {
      final (code, out, _) = await run(['explain', 'sec003']);
      expect(code, 0);
      expect(out, startsWith('SEC003 — '));
      expect(out, contains('Catégorie : Sécurité'));
      expect(out, contains('Sévérité : High'));
      expect(out, contains('CWE-'));
      expect(out, contains('À éviter'));
      expect(out, contains('À écrire'));
      expect(out, contains('# check-script disable=SEC003'));
      expect(out, contains('rules.disabled: [SEC003]'));
    });

    test('anglais, et équivalents dans d\'autres outils', () async {
      final (code, out, _) = await run(['explain', 'B602'], lang: 'en');
      expect(code, 0);
      expect(out, contains('Category'));
      expect(out, contains('Equivalent in other tools : S602'));
    });

    test('plusieurs règles, séparées', () async {
      final (code, out, _) = await run(['explain', 'SEC003', 'ROB005']);
      expect(code, 0);
      expect(out, contains('SEC003'));
      expect(out, contains('ROB005'));
      expect(out, contains('─' * 20));
    });

    test('règle inconnue : suggestions et code 2', () async {
      final (code, out, err) = await run(['explain', 'SEC00']);
      expect(code, 2);
      expect(out, isEmpty);
      expect(err, contains('Règle inconnue : SEC00'));
      expect(err, contains('SEC003'));
    });

    test('règle personnalisée de la configuration', () async {
      write('c.yaml', '''
rules:
  custom:
    - id: ACME001
      pattern: 'set -euo pipefail'
      absent: true
      message: Toujours set -euo pipefail
''');
      final (code, out, _) =
          await run(['explain', 'acme001', '--config', '${tmp.path}/c.yaml']);
      expect(code, 0);
      expect(out, contains('ACME001 — Toujours set -euo pipefail'));
      expect(out, contains('Outil : custom'));
    });

    test('sans règle : usage ; --help ; configuration invalide', () async {
      final (code, _, err) = await run(['explain']);
      expect(code, 2);
      expect(err, contains('Usage : check-script explain'));
      final (h, out, _) = await run(['explain', '--help']);
      expect(h, 0);
      expect(out, contains('Usage : check-script explain'));
      write('bad.yaml', 'profile: nope\n');
      final (c, _, e) =
          await run(['explain', 'SEC003', '--config', '${tmp.path}/bad.yaml']);
      expect(c, 2);
      expect(e, contains('Configuration invalide'));
    });

    test('toutes les règles intégrées ont une page', () {
      for (final e in knownRules(Lang.en)) {
        final text = renderRuleDoc(e, Lang.en);
        expect(text, startsWith(e.id));
        expect(text, contains('check-script disable=${e.id}'));
      }
    });
  });

  group('check-script init', () {
    test('profil suggéré : legacy pour du code qui a beaucoup de défauts',
        () async {
      write('a.sh', bad);
      write('b.sh', bad);
      final (code, _, err) = await run(['init', tmp.path, '--no-external']);
      expect(code, 0);
      expect(err, contains('Configuration écrite'));
      expect(err, contains('profil legacy'));
      final text = File('${tmp.path}/.checkscript.yaml').readAsStringSync();
      expect(text, contains('profile: legacy'));
      expect(text, contains('note moyenne'));
      // Le fichier généré est relu sans erreur par la CLI.
      expect(CheckConfig.parse(text).profile, Profile.legacy);
    });

    test('profil strict pour du code propre, default entre les deux', () {
      final clean1 = [
        for (var i = 0; i < 3; i++)
          () {
            final r = Engine(config: const CheckConfig(), runner: noTools());
            return r.analyze(script(clean));
          }()
      ];
      return Future.wait(clean1).then((reports) {
        expect(suggestProfile(reports), Profile.strict);
        expect(suggestProfile(const []), Profile.standard);
      });
    });

    test('dossier sans script : profil default', () async {
      final (code, _, err) = await run(['init', tmp.path, '--no-external']);
      expect(code, 0);
      expect(err, contains('profil default'));
      expect(File('${tmp.path}/.checkscript.yaml').readAsStringSync(),
          contains('aucun script trouvé'));
    });

    test('--profile, --context, --exclude : imposés, sans analyse', () async {
      write('a.sh', bad);
      final (code, _, _) = await run([
        'init',
        tmp.path,
        '--profile',
        'strict',
        '--context',
        'root',
        '--context',
        'cron',
        '--exclude',
        'vendor/',
        '--exclude',
        '*.min.sh',
      ]);
      expect(code, 0);
      final text = File('${tmp.path}/.checkscript.yaml').readAsStringSync();
      expect(text, contains('profile: strict'));
      expect(text, isNot(contains('note moyenne')));
      final c = CheckConfig.parse(text);
      expect(c.profile, Profile.strict);
      expect(c.contexts, {ExecContext.root, ExecContext.cron});
      expect(c.exclude, ['vendor/', '*.min.sh']);
    });

    test('ne remplace pas un fichier existant sans --force', () async {
      write('.checkscript.yaml', 'profile: legacy\n');
      final (code, _, err) = await run(['init', tmp.path, '--no-analysis']);
      expect(code, 2);
      expect(err, contains('existe déjà'));
      expect(File('${tmp.path}/.checkscript.yaml').readAsStringSync(),
          'profile: legacy\n');
      final (c2, _, _) =
          await run(['init', tmp.path, '--no-analysis', '--force']);
      expect(c2, 0);
      expect(File('${tmp.path}/.checkscript.yaml').readAsStringSync(),
          contains('profile: default'));
    });

    test('--stdout : rien d\'écrit, même si le fichier existe', () async {
      write('.checkscript.yaml', 'profile: legacy\n');
      final (code, out, _) =
          await run(['init', tmp.path, '--no-analysis', '--stdout']);
      expect(code, 0);
      expect(out, contains('profile: default'));
      expect(File('${tmp.path}/.checkscript.yaml').readAsStringSync(),
          'profile: legacy\n');
    });

    test('--baseline : rapport JSON relisible par --baseline', () async {
      write('a.sh', bad);
      final base = '${tmp.path}/base.json';
      final (code, _, err) =
          await run(['init', tmp.path, '--no-external', '--baseline', base]);
      expect(code, 0);
      expect(err, contains('Référence écrite'));
      final json = jsonDecode(File(base).readAsStringSync());
      expect(json, isNotNull);
      // Tous les problèmes déjà connus : aucun « nouveau ».
      final (c2, out, _) = await run([
        '--no-external',
        '--baseline',
        base,
        '--fail-on-new',
        'low',
        '--summary',
        '${tmp.path}/a.sh',
      ]);
      expect(c2, 0, reason: out);
    });

    test('dossier introuvable, argument en trop, option inconnue', () async {
      expect((await run(['init', '${tmp.path}/nope'])).$1, 3);
      expect((await run(['init', tmp.path, tmp.path])).$1, 2);
      expect((await run(['init', '--zzz'])).$1, 2);
    });

    test('anglais : commentaires traduits', () async {
      final (code, out, _) = await run(
          ['init', tmp.path, '--no-analysis', '--stdout'],
          lang: 'en');
      expect(code, 0);
      expect(out, contains('Scoring profile'));
      expect(out, isNot(contains('Profil de notation')));
    });

    test('--help', () async {
      final (code, out, _) = await run(['init', '--help']);
      expect(code, 0);
      expect(out, contains('--baseline FICHIER'));
    });

    test('exclusions du dossier prises en compte par l\'analyse', () async {
      write('a.sh', clean);
      write('vendor/x.sh', bad);
      write('vendor/y.sh', bad);
      final (_, _, _) = await run(
          ['init', tmp.path, '--no-external', '--exclude', 'vendor/']);
      // Sans l'exclusion, la moyenne serait faible (legacy).
      expect(File('${tmp.path}/.checkscript.yaml').readAsStringSync(),
          isNot(contains('profile: legacy')));
    });
  });
}
