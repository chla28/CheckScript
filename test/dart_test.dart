import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:check_script/src/analyzers/dart_tools.dart';
import 'package:check_script/src/analyzers/lang_rules.dart' show runLangRules;
import 'package:test/test.dart';

import 'helpers.dart';

String fx(String name) => readFixture('outputs/dart/$name');

ScriptInfo dartScript(String code, {String path = 'x.dart'}) =>
    ScriptInfo.fromContent(path, code, forcedDialect: Dialect.dart);

Set<String> rules(String code, {CheckConfig config = const CheckConfig()}) =>
    ids(runLangRules(dartScript(code), config, Lang.en));

void main() {
  group('dialecte', () {
    test('extension, shebang, commentaires', () {
      expect(ScriptInfo.dialectFromPath('a.dart'), Dialect.dart);
      expect(
          ScriptInfo.dialectFromShebang('#!/usr/bin/env dart'), Dialect.dart);
      expect(ScriptInfo.dialectFromShebang('#!/usr/bin/dart'), Dialect.dart);
      expect(Dialect.dart.languageName, 'dart');
      final s = script('// a\n/// b\n/* c\n * d */\nvoid main() {}\n',
          path: 'a.dart');
      expect((s.codeLines, s.commentLines), (1, 4));
    });

    test('un .dart est analysé seulement avec un shebang dans un dossier',
        () async {
      final d = Directory.systemTemp.createTempSync('cs_dart_');
      addTearDown(() => d.deleteSync(recursive: true));
      File('${d.path}/lib.dart').writeAsStringSync('void f() {}\n');
      File('${d.path}/tool.dart')
          .writeAsStringSync('#!/usr/bin/env dart\nvoid main() {}\n');
      final found = (await collectScripts(d.path))!
          .map((p) => p.split('/').last)
          .toList();
      expect(found, ['tool.dart']);
      expect(
          await collectScripts('${d.path}/lib.dart'), ['${d.path}/lib.dart']);
    });

    test('serveur LSP : .dart seulement avec shebang', () {
      expect(
          LspServer.isAnalyzable('/a/lib.dart', 'void f() {}\n', ''), isFalse);
      expect(
          LspServer.isAnalyzable(
              '/a/tool.dart', '#!/usr/bin/env dart\nvoid main() {}\n', ''),
          isTrue);
    });
  });

  group('règles lexicales', () {
    test('code en commentaire ignoré, chaînes respectées', () {
      expect(rules('// Process.run("sh", ["-c", "rm \$d"]);'),
          isNot(contains('DTSEC002')));
      expect(
          rules('/* import \'dart:mirrors\'; */'), isNot(contains('DTSEC003')));
      expect(rules("final u = 'a // http://b.fr';\n"),
          isNot(contains('DTSEC007')));
    });

    test('injection de commande : liste correcte, shell -c incorrect', () {
      expect(rules("await Process.run('rm', ['-rf', dir]);"),
          isNot(contains('DTSEC002')));
      expect(
          rules("await Process.run('sh', ['-c', cmd]);"), contains('DTSEC002'));
      expect(rules(r'await Process.run("rm -rf $dir", []);'),
          contains('DTSEC002'));
      expect(rules(r"await Process.run('ls', [dir], runInShell: true); // $x"),
          isNot(contains('DTSEC002')));
    });

    test('TLS : rappel permissif seulement', () {
      expect(rules('c.badCertificateCallback = (cert, host, port) => true;'),
          contains('DTSEC004'));
      expect(
          rules(
              'c.badCertificateCallback = (cert, host, port) {\n return true;\n};'),
          isNot(contains('DTSEC004')),
          reason: 'forme multi-ligne non couverte (documenté)');
      expect(rules('c.badCertificateCallback = (cert, host, port) => false;'),
          isNot(contains('DTSEC004')));
    });

    test('Random : sécurisé accepté, seulement pour un secret', () {
      expect(rules('final token = Random.secure().nextInt(9);'),
          isNot(contains('DTSEC006')));
      expect(
          rules('final x = Random().nextInt(9);'), isNot(contains('DTSEC006')));
      expect(
          rules('final salt = Random(42).nextInt(9);'), contains('DTSEC006'));
    });

    test('http:// : exceptions locales et espaces de noms', () {
      for (final ok in [
        "final a = 'http://localhost:8080/x';",
        "final a = 'http://127.0.0.1/x';",
        "final a = 'http://10.0.2.2:3000';",
        "final a = 'http://www.w3.org/2000/svg';",
        "final a = 'http://example.com/x';",
      ]) {
        expect(rules(ok), isNot(contains('DTSEC007')), reason: ok);
      }
      expect(
          rules("final a = 'http://api.monsite.fr/v1';"), contains('DTSEC007'));
    });

    test('SQL : paramètres corrects, interpolation et concaténation non', () {
      expect(rules("db.rawQuery('SELECT * FROM t WHERE id = ?', [id]);"),
          isNot(contains('DTSEC008')));
      expect(rules(r"db.rawQuery('SELECT * FROM t WHERE id = $id');"),
          contains('DTSEC008'));
      expect(rules('''db.rawQuery("SELECT * FROM t WHERE n = '\$n'");'''),
          contains('DTSEC008'));
      expect(rules("db.execute('DELETE FROM t WHERE id = ' + id);"),
          contains('DTSEC008'));
      expect(rules(r"foo.execute('echo $x');"), isNot(contains('DTSEC008')));
    });

    test('journaux et préférences', () {
      expect(rules(r"print('token = $token');"), contains('DTSEC009'));
      expect(rules("print('Entrez votre mot de passe');"),
          isNot(contains('DTSEC009')));
      expect(rules("prefs.setString('auth_token', t);"), contains('DTSEC010'));
      expect(
          rules("prefs.setString('theme', t);"), isNot(contains('DTSEC010')));
    });

    test('catch vide, y compris sur plusieurs lignes', () {
      final f = runLangRules(
          dartScript(
              'void f() {\n  try {\n    g();\n  } catch (e) {\n  }\n}\n'),
          const CheckConfig(),
          Lang.en);
      final hit = f.firstWhere((x) => x.ruleId == 'DTROB001');
      expect(hit.line, 4);
      expect(hit.equivalents, contains('empty_catches'));
      expect(rules('try { g(); } catch (e) { log(e); }'),
          isNot(contains('DTROB001')));
    });

    test('readLineSync : seulement sans terminal (cron, systemd)', () {
      const code = 'final a = stdin.readLineSync();';
      expect(rules(code), isNot(contains('DTROB002')));
      expect(
          rules(code, config: const CheckConfig(contexts: {ExecContext.cron})),
          contains('DTROB002'));
    });

    test('http sans délai : délai sur la ligne ou la suivante accepté', () {
      expect(rules('final r = await http.get(u);'), contains('DTROB003'));
      expect(rules('final r = await http.get(u).timeout(t);'),
          isNot(contains('DTROB003')));
      expect(rules('final r = await http\n    .get(u)\n    .timeout(t);'),
          isNot(contains('DTROB003')));
    });

    test('directive de suppression dans un commentaire //', () async {
      final e = Engine(runner: noTools(), lang: Lang.en);
      final r = await e.analyze(
          dartScript(
              "final t = Random().nextInt(9) + token; // check-script disable=DTSEC006\n"),
          filePath: 'x.dart');
      expect(ids(r.findings), isNot(contains('DTSEC006')));
    });
  });

  group('dart analyze (sorties réelles)', () {
    test('erreurs et avertissements classés, syntaxe écartée', () {
      final f = parseDartAnalyze(fx('analyze.txt'));
      expect(f.map((x) => x.ruleId), [
        'URI_DOES_NOT_EXIST',
        'UNDEFINED_IDENTIFIER',
        'INVALID_ASSIGNMENT',
        'UNUSED_LOCAL_VARIABLE',
        'UNUSED_LOCAL_VARIABLE',
      ]);
      final err = f[1];
      expect(
          (err.category, err.severity), (Category.robustness, Severity.high));
      expect((err.line, err.column), (7, 9));
      expect(err.message, "Undefined name 'undefinedThing'.");
      final unused = f[3];
      expect((unused.category, unused.severity),
          (Category.maintainability, Severity.low));
    });

    test('analyse hors projet : paquets non résolus écartés', () {
      final f = parseDartAnalyze(fx('analyze.txt'), detached: true);
      expect(f.map((x) => x.ruleId), [
        'INVALID_ASSIGNMENT',
        'UNUSED_LOCAL_VARIABLE',
        'UNUSED_LOCAL_VARIABLE'
      ]);
    });

    test('lints : nom usuel, classement et lien', () {
      final f = parseDartAnalyze(fx('analyze-lints.txt'));
      expect(f.map((x) => x.ruleId),
          ['UNUSED_IMPORT', 'avoid_print', 'empty_catches']);
      expect(f[1].category, Category.maintainability);
      expect(f[2].category, Category.robustness);
      expect(f[1].url, 'https://dart.dev/tools/linter-rules/avoid_print');
      expect(f[0].url, isNull);
    });

    test('ligne illisible ou message contenant « \\| »', () {
      expect(parseDartAnalyze('Analyzing x...\nNo issues found!\n'), isEmpty);
      final f = parseDartAnalyze(
          r'INFO|LINT|AVOID_PRINT|/p/a.dart|4|3|5|a \| b \\ c');
      expect(f.single.message, r'a | b \ c');
    });

    test('analyseur : exécution, exclusions et outil absent', () async {
      final runner = FakeRunner({
        'dart': (args) => args.first == 'analyze'
            ? CommandResult(3, fx('analyze-lints.txt'), '')
            : const CommandResult(0, '', ''),
      });
      final e = Engine(
          runner: runner,
          lang: Lang.en,
          config: CheckConfig.parse(
              'tools:\n  dart-analyze:\n    exclude: [unused_import]\n'));
      final r =
          await e.analyze(dartScript('void main() {}\n'), filePath: 'x.dart');
      expect(r.findings.map((f) => f.ruleId),
          containsAll(['avoid_print', 'empty_catches']));
      expect(r.findings.map((f) => f.ruleId), isNot(contains('UNUSED_IMPORT')));
      final call = runner.calls.firstWhere((c) => c.$2.first == 'analyze').$2;
      expect(call, contains('--format=machine'));

      final none = Engine(runner: noTools(), lang: Lang.en);
      final r2 = await none.analyze(dartScript('void main() {}\n'),
          filePath: 'x.dart');
      expect(
          r2.tools
              .where((t) => t.tool.startsWith('dart-'))
              .map((t) => t.status),
          everyElement(ToolStatus.missing));
    });
  });

  group('dart format et syntaxe', () {
    test('fichier à reformater : un problème de fichier', () async {
      final runner = FakeRunner({
        'dart': (args) =>
            args.first == 'format' && args.contains('--set-exit-if-changed')
                ? const CommandResult(1, 'Changed x.dart', '')
                : const CommandResult(0, '', ''),
      });
      final r = await Engine(runner: runner, lang: Lang.en)
          .analyze(dartScript('void main() {}\n'), filePath: 'x.dart');
      final f = r.findings.firstWhere((f) => f.tool == 'dart-format');
      expect((f.ruleId, f.line), ('FORMAT', 0));
    });

    test('erreur de syntaxe : une seule fois, au bon endroit', () async {
      final syntax = fx('format-syntax-error.txt');
      final runner = FakeRunner({
        'dart': (args) => args.first == 'format'
            ? CommandResult(65, '', syntax)
            : CommandResult(3, '', ''),
      });
      final r = await Engine(runner: runner, lang: Lang.en).analyze(
          dartScript('void main() {\n  var = ;\n'),
          filePath: 'x.dart');
      final errs = r.findings.where((f) => f.ruleId == 'SYNTAX').toList();
      expect(errs, hasLength(1));
      expect(errs.single.line, 2);
      expect(errs.single.message, 'Expected an identifier.');
      // Un fichier qui ne se formate pas n'est pas « non formaté ».
      expect(r.findings.where((f) => f.tool == 'dart-format'), isEmpty);
    });

    test('analyse sans outil Dart : les règles intégrées restent', () async {
      final r = await Engine(runner: noTools(), lang: Lang.en).analyze(
          dartScript("final u = 'http://api.monsite.fr';\n"),
          filePath: 'x.dart');
      expect(ids(r.findings), contains('DTSEC007'));
    });
  });

  group('coloration', () {
    test('Dart : mots-clés, chaînes, commentaires de bloc', () {
      final lines = ["final s = 'a'; // c", '/* b', 'c */ var x = 1;'];
      final t = highlightLines(lines, HighlightLanguage.dart);
      String show(int i) => t[i]
          .map((k) => '${k.kind.name}:${lines[i].substring(k.start, k.end)}')
          .join(' ');
      expect(show(0), 'keyword:final string:\'a\' comment:// c');
      expect(show(1), 'comment:/* b');
      expect(show(2), 'comment:c */ keyword:var number:1');
      expect(HighlightLanguage.of(script('x\n', path: 'a.dart')),
          HighlightLanguage.dart);
    });
  });
}
