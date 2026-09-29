import 'dart:async';
import 'dart:io';

import 'package:check_script/check_script.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Client LSP de test : envoie des messages au serveur et lit ses réponses.
class Client implements StreamConsumer<List<int>> {
  Client(CommandRunner runner) {
    server = LspServer(_in.stream, IOSink(this), runner: runner, lang: Lang.fr);
    done = server.serve();
  }

  final _in = StreamController<List<int>>();
  final _out = StreamController<List<int>>();
  late final LspServer server;
  late final Future<int> done;
  late final received = lspMessages(_out.stream).asBroadcastStream();
  final inbox = <Map<String, Object?>>[];
  late final _sub = received.listen(inbox.add);
  var _id = 0;

  @override
  Future<void> addStream(Stream<List<int>> s) => s.forEach(_out.add);
  @override
  Future<void> close() async {}

  void notify(String method, [Object? params]) {
    _sub;
    _in.add(lspFrame({
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params
    }));
  }

  Future<Object?> request(String method, [Object? params]) async {
    _sub;
    final id = ++_id;
    _in.add(lspFrame({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    }));
    final r = await waitFor((m) => m['id'] == id);
    if (r['error'] != null) throw StateError('${r['error']}');
    return r['result'];
  }

  Future<Map<String, Object?>> waitFor(bool Function(Map<String, Object?>) ok,
      {bool consume = true}) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final i = inbox.indexWhere(ok);
      if (i >= 0) return consume ? inbox.removeAt(i) : inbox[i];
      if (DateTime.now().isAfter(end)) throw TimeoutException('LSP');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<List<Map>> diagnostics(String uri) async {
    final m = await waitFor((m) =>
        m['method'] == 'textDocument/publishDiagnostics' &&
        (m['params'] as Map)['uri'] == uri);
    return [
      for (final d in (m['params'] as Map)['diagnostics'] as List) d as Map
    ];
  }

  Future<int> stop() async {
    await request('shutdown');
    notify('exit');
    await _in.close();
    return done;
  }
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cs_lsp_'));
  tearDown(() => tmp.delete(recursive: true));

  test('trames JSON-RPC : découpage et accents', () async {
    final frames = [
      ...lspFrame({'a': 'é'}),
      ...lspFrame({'b': 2}),
    ];
    final chunks = Stream.fromIterable(
        [frames.sublist(0, 7), frames.sublist(7, 30), frames.sublist(30)]);
    expect(await lspMessages(chunks).toList(), [
      {'a': 'é'},
      {'b': 2}
    ]);
  });

  test('cycle complet : diagnostics, survol, corrections, frappe, fermeture',
      () async {
    final c = Client(noTools());
    final init = await c.request('initialize', {
      'processId': null,
      'rootUri': null,
      'capabilities': {},
      'initializationOptions': {'lang': 'fr', 'typingDelay': 20},
    }) as Map;
    expect((init['capabilities'] as Map)['hoverProvider'], isTrue);
    expect((init['serverInfo'] as Map)['name'], 'check-script');
    c.notify('initialized', {});

    final f = File('${tmp.path}/a.sh')
      ..writeAsStringSync('#!/bin/bash\ncd /opt\negrep a f\negrep b f\n');
    final uri = f.uri.toString();
    c.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': 'shellscript',
        'version': 1,
        'text': f.readAsStringSync(),
      }
    });
    final diags = await c.diagnostics(uri);
    Map diag(String code) => diags.firstWhere((d) => d['code'] == code);
    final egrep = diag('POR005');
    expect((egrep['range'] as Map)['start'], {'line': 2, 'character': 0});
    expect(egrep['source'], 'check-script');
    expect(egrep['message'], contains('→'));
    final score = await c.waitFor((m) => m['method'] == 'checkScript/score');
    expect((score['params'] as Map)['grade'], isNotEmpty);

    final hover = await c.request('textDocument/hover', {
      'textDocument': {'uri': uri},
      'position': {'line': 2, 'character': 1},
    }) as Map;
    final md = (hover['contents'] as Map)['value'] as String;
    expect(md, contains('**POR005**'));
    expect(md, contains('```sh'));
    expect(md, contains('À écrire'));

    final actions = await c.request('textDocument/codeAction', {
      'textDocument': {'uri': uri},
      'range': egrep['range'],
      'context': {
        'diagnostics': [egrep]
      },
    }) as List;
    final titles = [for (final a in actions) (a as Map)['title']];
    expect(titles, contains('Corriger : POR005'));
    expect(titles, contains('Corriger les 2 occurrences de POR005'));
    expect(titles, contains('Ignorer POR005 sur cette ligne'));
    expect(titles, contains('Ignorer POR005 dans tout le fichier'));
    final fix = actions.first as Map;
    final edit = ((fix['edit'] as Map)['changes'] as Map)[uri] as List;
    expect((edit.single as Map)['newText'], contains('grep -E'));
    final ignore = actions.firstWhere(
            (a) => (a as Map)['title'] == 'Ignorer POR005 dans tout le fichier')
        as Map;
    final ins = (((ignore['edit'] as Map)['changes'] as Map)[uri] as List)
        .single as Map;
    expect(ins['newText'], '# check-script disable-file=POR005\n');
    expect(
        ((ins['range'] as Map)['start'] as Map)['line'], 1); // après le shebang

    // Frappe : règles intégrées sur le texte en cours.
    c.notify('textDocument/didChange', {
      'textDocument': {'uri': uri, 'version': 2},
      'contentChanges': [
        {'text': '#!/bin/bash\ncd /opt\n'}
      ],
    });
    final typed = await c.diagnostics(uri);
    expect(typed.map((d) => d['code']), isNot(contains('POR005')));
    expect(typed.map((d) => d['code']), contains('ROB005'));

    c.notify('textDocument/didClose', {
      'textDocument': {'uri': uri}
    });
    expect(await c.diagnostics(uri), isEmpty);
    expect(await c.stop(), 0);
  });

  test('fichier non script ignoré ; formatage ; méthode inconnue', () async {
    final runner = FakeRunner({
      'shfmt': (args) =>
          const CommandResult(0, 'if true; then\n\techo a\nfi\n', ''),
    });
    final c = Client(runner);
    await c.request('initialize', {'capabilities': {}});
    final txt = '${tmp.uri}notes.txt';
    c.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': txt,
        'languageId': 'plaintext',
        'version': 1,
        'text': 'egrep a f\n',
      }
    });
    expect(await c.diagnostics(txt), isEmpty);
    final sh = '${tmp.uri}b.sh';
    c.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': sh,
        'languageId': 'shellscript',
        'version': 1,
        'text': 'if true; then\necho a\nfi\n',
      }
    });
    await c.diagnostics(sh);
    final edits = await c.request('textDocument/formatting', {
      'textDocument': {'uri': sh},
      'options': {'tabSize': 4, 'insertSpaces': true},
    }) as List;
    final e = edits.single as Map;
    expect(e['newText'], 'if true; then\n\techo a\nfi\n');
    expect((e['range'] as Map)['end'], {'line': 3, 'character': 0});
    await expectLater(c.request('textDocument/foo'), throwsStateError);
    expect(await c.stop(), 0);
  });

  test('check-script lsp : processus réel', () async {
    final p = await Process.start(
        Platform.resolvedExecutable, ['run', 'bin/check_script.dart', 'lsp']);
    final got = lspMessages(p.stdout).asBroadcastStream();
    p.stdin.add(lspFrame({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'capabilities': {}},
    }));
    await p.stdin.flush();
    final r = await got.first.timeout(const Duration(seconds: 60));
    expect(((r['result'] as Map)['serverInfo'] as Map)['version'], appVersion);
    p.stdin.add(lspFrame({'jsonrpc': '2.0', 'id': 2, 'method': 'shutdown'}));
    p.stdin.add(lspFrame({'jsonrpc': '2.0', 'method': 'exit'}));
    await p.stdin.close();
    expect(await p.exitCode.timeout(const Duration(seconds: 30)), 0);
    await p.stderr.drain<void>();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
