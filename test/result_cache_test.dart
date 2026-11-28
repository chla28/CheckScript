import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cs_cache_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<ScriptReport> report(ScriptInfo s) =>
      Engine(runner: noTools()).analyze(s);

  group('ResultCache', () {
    test('écriture puis relecture d\'un rapport', () async {
      final cache = ResultCache(Directory('${dir.path}/sub/results'));
      final s = script('#!/bin/bash\neval "\$x"\n');
      final r = await report(s);
      await cache.write('k1', r);
      final back = cache.read('k1', s);
      expect(back, isNotNull);
      expect(back!.findings.length, r.findings.length);
    });

    test('clé absente, JSON invalide ou non objet : null', () {
      final cache = ResultCache(dir);
      final s = script('echo a\n');
      expect(cache.read('absent', s), isNull);
      File('${dir.path}/bad.json').writeAsStringSync('{ pas du json');
      expect(cache.read('bad', s), isNull);
      File('${dir.path}/list.json').writeAsStringSync('[1, 2]');
      expect(cache.read('list', s), isNull);
    });

    test('la lecture rafraîchit la date de l\'entrée', () async {
      final cache = ResultCache(dir);
      final s = script('echo a\n');
      await cache.write('k', await report(s));
      final f = File('${dir.path}/k.json');
      f.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 20)));
      cache.read('k', s);
      expect(DateTime.now().difference(f.lastModifiedSync()).inMinutes,
          lessThan(5));
    });

    test('écriture impossible : erreur ignorée', () async {
      // Le « dossier » du cache est un fichier ordinaire.
      final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
      final cache = ResultCache(Directory(blocker.path));
      await cache.write('k', await report(script('echo a\n')));
      expect(blocker.readAsStringSync(), 'x');
    });

    test('prune retire seulement les entrées trop anciennes', () async {
      final cache = ResultCache(dir);
      final s = script('echo a\n');
      await cache.write('old', await report(s));
      await cache.write('new', await report(s));
      File('${dir.path}/old.json').setLastModifiedSync(DateTime.now()
          .subtract(ResultCache.maxAge + const Duration(days: 1)));
      await cache.prune();
      expect(File('${dir.path}/old.json').existsSync(), isFalse);
      expect(File('${dir.path}/new.json').existsSync(), isTrue);
    });

    test('prune sur un dossier inexistant : sans effet', () async {
      await ResultCache(Directory('${dir.path}/none')).prune();
    });

    test('emplacement par défaut : XDG_CACHE_HOME ou HOME', () {
      final d = ResultCache.defaultDir();
      final env = Platform.environment;
      if (env['XDG_CACHE_HOME'] != null) {
        expect(d!.path, '${env['XDG_CACHE_HOME']}/check-script/results');
      } else if (env['HOME'] != null) {
        expect(d!.path, '${env['HOME']}/.cache/check-script/results');
      } else {
        expect(d, isNull);
      }
      expect(ResultCache.standard() == null, d == null);
    });
  });
}
