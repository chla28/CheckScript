import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'cli_test.dart' show Capture;
import 'helpers.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cs_glob_');
    for (final f in [
      'a.sh',
      'b.py',
      'notes.txt',
      'sub/c.sh',
      'sub/deep/d.sh',
      '.hidden/e.sh',
    ]) {
      File('${tmp.path}/$f')
        ..createSync(recursive: true)
        ..writeAsStringSync('echo x\n');
    }
  });
  tearDown(() async => tmp.delete(recursive: true));

  List<String> names(Iterable<String> paths) => [
        for (final f in paths) f.substring(tmp.path.length + 1),
      ];

  Future<(int, String, String)> run(List<String> args) async {
    final out = Capture(), err = Capture();
    final code = await cli.run([...args, '--lang', 'fr'],
        out: out.sink, err: err.sink, runner: noTools());
    return (code, await out.text(), await err.text());
  }

  group('dossier', () {
    test('par défaut : le dossier lui-même, sans descendre', () async {
      final f = await collectScripts(tmp.path);
      expect(names(f!), ['a.sh', 'b.py']);
    });

    test('avec recursive : toute l\'arborescence, hors dossiers cachés',
        () async {
      final f = await collectScripts(tmp.path, recursive: true);
      expect(names(f!), ['a.sh', 'b.py', 'sub/c.sh', 'sub/deep/d.sh']);
    });

    test('CLI : -r nécessaire pour les sous-dossiers', () async {
      final (_, out1, _) = await run(['-f', 'json', tmp.path]);
      expect(out1, isNot(contains('c.sh')));
      final (_, out2, _) = await run(['-f', 'json', '-r', tmp.path]);
      expect(out2, contains('c.sh'));
      expect(out2, contains('d.sh'));
    });
  });

  group('motifs', () {
    test('hasGlob', () {
      expect(hasGlob('*.sh'), isTrue);
      expect(hasGlob('src/a?.sh'), isTrue);
      expect(hasGlob('a[12].sh'), isTrue);
      expect(hasGlob('script.sh'), isFalse);
    });

    test('*.sh : dossier courant seulement par défaut', () async {
      final r = await expandTargets(['${tmp.path}/*.sh']);
      expect(names(r), ['a.sh']);
    });

    test('*.sh avec recursive : à tout niveau (comme find -name)', () async {
      final r = await expandTargets(['${tmp.path}/*.sh'], recursive: true);
      expect(names(r), ['a.sh', 'sub/c.sh', 'sub/deep/d.sh']);
    });

    test('motif avec « / » : niveau précis ; ** traverse', () async {
      expect(
          names(await expandTargets(['${tmp.path}/sub/*.sh'])), ['sub/c.sh']);
      expect(names(await expandTargets(['${tmp.path}/**/*.sh'])),
          ['a.sh', 'sub/c.sh', 'sub/deep/d.sh']);
    });

    test('* ne ramène que des scripts et des dossiers', () async {
      final r = await expandTargets(['${tmp.path}/*']);
      expect(names(r), ['a.sh', 'b.py', 'sub']);
    });

    test('fichiers cachés exclus sauf motif explicite', () async {
      expect(names(await expandTargets(['${tmp.path}/*.sh'], recursive: true)),
          isNot(contains('.hidden/e.sh')));
      expect(names(await expandTargets(['${tmp.path}/.hidden/*.sh'])),
          ['.hidden/e.sh']);
    });

    test('classe [] et ?', () async {
      expect(
          names(await expandTargets(['${tmp.path}/[ab].*'])), ['a.sh', 'b.py']);
      expect(names(await expandTargets(['${tmp.path}/?.py'])), ['b.py']);
    });

    test('sans correspondance : motif conservé ; chemin existant inchangé',
        () async {
      expect(await expandTargets(['${tmp.path}/*.zsh']), ['${tmp.path}/*.zsh']);
      expect(await expandTargets(['-', '${tmp.path}/a.sh']),
          ['-', '${tmp.path}/a.sh']);
    });

    test('CLI : motif protégé développé par l\'outil', () async {
      final (code, out, _) = await run(['-f', 'json', '${tmp.path}/*.sh']);
      expect(code, 0);
      expect(out, contains('a.sh'));
      expect(out, isNot(contains('c.sh')));
    });

    test('CLI : motif sans résultat → introuvable', () async {
      final (code, _, err) = await run(['${tmp.path}/*.zsh']);
      expect(code, cli.exitInput);
      expect(err, contains('Introuvable'));
    });
  });
}
