import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../bin/check_script.dart' as cli;
import 'helpers.dart';

/// Sortie capturée au fil de l'eau (lisible pendant --watch).
class Live implements StreamConsumer<List<int>> {
  final buffer = StringBuffer();
  late final IOSink sink = IOSink(this);
  @override
  Future<void> addStream(Stream<List<int>> s) =>
      s.forEach((b) => buffer.write(utf8.decode(b)));
  @override
  Future<void> close() async {}
}

Future<void> until(bool Function() ok, {int seconds = 10}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('attente');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_014_'));
  tearDown(() => tmp.delete(recursive: true));

  Future<List<ScriptReport>> reports() async => [
        await Engine(runner: noTools(), lang: Lang.fr).analyze(script(
            '#!/bin/bash\necho "<&>"\negrep a f\n',
            path: './scripts/a.sh')),
        await Engine(runner: noTools(), lang: Lang.fr).analyze(
            script('#!/bin/sh\n# ok\nset -eu\necho b\n', path: 'b.sh')),
      ];

  test('JUnit XML : une suite par script, un échec par problème', () async {
    final r = await reports();
    final xml = renderJunit(r);
    final n = r[0].findings.length;
    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml,
        contains('<testsuite name="scripts/a.sh" tests="$n" failures="$n"'));
    expect(xml, contains('name="POR005:3"'));
    expect(xml, contains('<failure type="'));
    // Script sans problème : un cas réussi.
    if (r[1].findings.isEmpty) {
      expect(xml, contains('<testcase classname="b.sh" name="check-script"/>'));
    }
    expect(OutputFormat.fromPath('rapport.xml'), OutputFormat.junit);
    expect(OutputFormat.tryParse('junit'), OutputFormat.junit);
    // Bien formé (si python3 est là pour le vérifier).
    try {
      final p = await Process.start('python3', [
        '-c',
        'import sys, xml.dom.minidom as m; m.parseString(sys.stdin.read())'
      ]);
      p.stdin.write(xml);
      await p.stdin.close();
      expect(await p.exitCode, 0);
    } on ProcessException {
      // python3 absent.
    }
  });

  test('annotations GitHub : niveau, position, échappement', () async {
    final r = await reports();
    final out = renderGithub(r);
    final line = out.split('\n').firstWhere((l) => l.contains('POR005'));
    expect(line, startsWith('::'));
    expect(line, contains('file=scripts/a.sh,line=3'));
    expect(line, contains('title=POR005 (builtin%2C '));
    expect(renderGithub(r).contains('\n\n'), isFalse);
    expect(OutputFormat.tryParse('github'), OutputFormat.github);
  });

  test('l\'extension d\'un fichier -o prime sur --format', () async {
    final f = File('${tmp.path}/s.sh')..writeAsStringSync('#!/bin/sh\necho\n');
    final out = Live(), err = Live();
    final code = await cli.run([
      '--lang',
      'fr',
      '--no-cache',
      '-f',
      'github',
      '-o',
      '${tmp.path}/r.json',
      '-o',
      '${tmp.path}/r.xml',
      f.path,
    ], out: out.sink, err: err.sink, runner: noTools());
    await out.sink.flush();
    expect(code, 0);
    expect(jsonDecode(File('${tmp.path}/r.json').readAsStringSync())['tool'],
        'check-script');
    expect(
        File('${tmp.path}/r.xml').readAsStringSync(), contains('<testsuites'));
    // La sortie standard suit --format.
    expect(out.buffer.toString(), isNot(contains('Note globale')));
  });

  test('--watch : réanalyse le script enregistré', () async {
    final f = File('${tmp.path}/a.sh')
      ..writeAsStringSync('#!/bin/sh\necho a\n');
    final out = Live(), err = Live();
    final stop = Completer<void>();
    final done = cli.run(['--lang', 'fr', '--no-cache', '--watch', tmp.path],
        out: out.sink,
        err: err.sink,
        runner: noTools(),
        stopWatching: stop.future);
    await until(() => err.buffer.toString().contains('Surveillance'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    f.writeAsStringSync('#!/bin/sh\negrep a f\n');
    await until(() => out.buffer.toString().contains('── '));
    await until(() => out.buffer.toString().contains('POR005'));
    stop.complete();
    expect(await done, 0);
    expect(
        await cli.run(['--watch', '--fix', f.path],
            out: IOSink(Live()), err: IOSink(Live()), runner: noTools()),
        2);
  });

  test('surveillance : sous-dossiers, dossiers créés, dossiers cachés ignorés',
      () async {
    Directory('${tmp.path}/sub').createSync();
    Directory('${tmp.path}/.cache').createSync();
    final batches = <Set<String>>[];
    final sub =
        watchTargets([tmp.path], debounce: const Duration(milliseconds: 150))
            .listen(batches.add);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    File('${tmp.path}/sub/a.sh').writeAsStringSync('x');
    File('${tmp.path}/.cache/b.sh').writeAsStringSync('x');
    await until(() => batches.isNotEmpty);
    Directory('${tmp.path}/new').createSync();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    File('${tmp.path}/new/c.sh').writeAsStringSync('x');
    await until(() => batches.expand((b) => b).any((p) => p.endsWith('c.sh')));
    await sub.cancel();
    final all = batches.expand((b) => b).toSet();
    expect(all.any((p) => p.endsWith('sub/a.sh')), isTrue);
    expect(all.any((p) => p.contains('.cache')), isFalse);
  });

  test('action.yml : entrées, sorties, étapes', () {
    final a = loadYaml(File('action.yml').readAsStringSync()) as YamlMap;
    expect(a['runs']['using'], 'composite');
    expect((a['inputs'] as YamlMap).keys,
        containsAll(['paths', 'fail-under', 'sarif', 'annotations']));
    expect((a['outputs'] as YamlMap).keys, containsAll(['score', 'grade']));
    // Paramètres jamais interpolés dans le script (injection) : SEC023.
    final run = (a['runs']['steps'] as YamlList)
        .firstWhere((s) => s['id'] == 'run')['run'] as String;
    expect(run, isNot(contains(r'${{')));
    final e = extractEmbedded(
        EmbeddedKind.githubActions, File('action.yml').readAsStringSync());
    expect(e.issues, isEmpty);
    expect(e.blocks, isNotEmpty);
  });
}
