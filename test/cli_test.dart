import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import '../bin/check_script.dart' as cli;
import 'helpers.dart';

class Capture implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  late final IOSink sink = IOSink(this);

  @override
  Future<void> addStream(Stream<List<int>> s) => s.forEach(bytes.addAll);
  @override
  Future<void> close() async {}

  Future<String> text() async {
    await sink.flush();
    return utf8.decode(bytes);
  }
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_cli_'));
  tearDown(() async => tmp.delete(recursive: true));

  Future<(int, String, String)> run(List<String> args) async {
    final out = Capture(), err = Capture();
    final code =
        await cli.run(args, out: out.sink, err: err.sink, runner: noTools());
    return (code, await out.text(), await err.text());
  }

  test('--version', () async {
    final (code, out, _) = await run(['--version']);
    expect(code, cli.exitOk);
    expect(out.trim(), 'check-script $appVersion');
  });

  test('--help en français et en anglais', () async {
    expect((await run(['--help', '--lang', 'fr'])).$2,
        contains('Usage : check-script'));
    expect((await run(['--lang=en', '--help'])).$2,
        contains('Usage: check-script'));
  });

  test('aucun argument : erreur d\'usage', () async {
    expect((await run([])).$1, cli.exitUsage);
  });

  test('option inconnue : erreur d\'usage', () async {
    expect((await run(['--nope'])).$1, cli.exitUsage);
  });

  test('fichier introuvable : code 3', () async {
    final (code, _, err) = await run(['--lang', 'fr', 'absent.sh']);
    expect(code, cli.exitInput);
    expect(err, contains('Introuvable'));
  });

  test('analyse terminal', () async {
    final (code, out, _) = await run(['--lang', 'fr', fixture('bad.sh')]);
    expect(code, cli.exitOk);
    expect(out, contains('Sécurité'));
    expect(out, contains('Note globale'));
    expect(out.contains('\x1B['), isFalse);
  });

  test('sorties .md, .adoc et .json + --quiet', () async {
    final md = '${tmp.path}/r.md',
        ad = '${tmp.path}/sub/r.adoc',
        js = '${tmp.path}/r.json';
    final (code, out, err) =
        await run(['-q', '-o', md, '-o', ad, '-o', js, fixture('bad.sh')]);
    expect(code, cli.exitOk);
    expect(out, isEmpty);
    expect(err, contains(md));
    expect(File(md).readAsStringSync(), contains('| Critical |'));
    expect(File(ad).readAsStringSync(), contains('|==='));
    expect(jsonDecode(File(js).readAsStringSync()), contains('reports'));
  });

  test('--format json sur la sortie standard', () async {
    final (_, out, _) = await run(['-f', 'json', fixture('good.sh')]);
    expect(jsonDecode(out)['reports'], hasLength(1));
  });

  test('--fail-under', () async {
    expect((await run(['-q', '--fail-under', '9', fixture('bad.sh')])).$1,
        cli.exitBelowThreshold);
    expect((await run(['-q', '--fail-under', '5', fixture('good.sh')])).$1,
        cli.exitOk);
    expect((await run(['-q', '--fail-under', '11', fixture('good.sh')])).$1,
        cli.exitUsage);
  });

  test('dossier : scripts trouvés par extension ou shebang', () async {
    File('${tmp.path}/a.sh').writeAsStringSync('echo a\n');
    File('${tmp.path}/tool').writeAsStringSync('#!/usr/bin/env bash\necho b\n');
    File('${tmp.path}/notes.txt').writeAsStringSync('texte\n');
    Directory('${tmp.path}/.git').createSync();
    File('${tmp.path}/.git/hook.sh').writeAsStringSync('echo c\n');
    final files = await cli.collectScripts(tmp.path);
    expect(files!.map((f) => f.split('/').last), ['a.sh', 'tool']);
  });

  test('configuration invalide : code 2', () async {
    final c = File('${tmp.path}/c.yaml')..writeAsStringSync('- liste');
    expect((await run(['-c', c.path, fixture('good.sh')])).$1, cli.exitUsage);
  });

  test('--list-rules et --list-tools', () async {
    expect((await run(['--list-rules'])).$2, contains('SEC001'));
    final tools = (await run(['--list-tools', '--lang', 'en'])).$2;
    expect(tools, contains('shellcheck'));
    expect(tools, contains('not installed'));
  });
}
