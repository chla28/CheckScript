/// Serveur LSP (Language Server Protocol) : `check-script lsp`, lancé par
/// les extensions d'éditeurs (VS Code, Eclipse via LSP4E, Geany, Neovim…).
///
/// * diagnostics : analyse complète à l'ouverture et à l'enregistrement ;
///   pendant la frappe (après une pause), règles intégrées sur le texte en
///   cours, les résultats des outils externes restant affichés tant que leur
///   ligne n'a pas changé ;
/// * corrections rapides : correction d'un problème ou de toute la règle,
///   directive `# check-script disable=…` (ligne ou fichier) ;
/// * survol : message, conseil, exemple « à éviter / à écrire », lien ;
/// * formatage : shfmt ou `ruff format` ;
/// * notification `checkScript/score` (note du script) pour la barre d'état.
///
/// Options d'initialisation (`initializationOptions`, ou
/// `workspace/didChangeConfiguration` → `settings.checkScript`) : `lang`
/// (fr, en), `profile` (strict, default, legacy), `analyzeOnType` (true),
/// `typingDelay` (ms, 600).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../analyzers/analyzer.dart';
import '../analyzers/builtin_rules.dart' show BuiltinAnalyzer;
import '../analyzers/external_tools.dart' show SyntaxAnalyzer;
import '../config.dart';
import '../config_discovery.dart';
import '../embedded.dart';
import '../engine.dart';
import '../fixer.dart';
import '../i18n.dart';
import '../model/finding.dart';
import '../model/report.dart';
import '../rules/custom_rules.dart';
import '../rules/examples.dart';
import '../rules/references.dart';
import '../script_info.dart';
import '../version.dart';

/// Lit les messages JSON-RPC d'un flux (en-têtes `Content-Length`).
Stream<Map<String, Object?>> lspMessages(Stream<List<int>> input) async* {
  final buf = <int>[];
  await for (final chunk in input) {
    buf.addAll(chunk);
    while (true) {
      final sep = _indexOf(buf, const [13, 10, 13, 10]);
      if (sep < 0) break;
      final headers = ascii.decode(buf.sublist(0, sep), allowInvalid: true);
      final m = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false)
          .firstMatch(headers);
      if (m == null) {
        buf.removeRange(0, sep + 4); // en-tête invalide : ignoré
        continue;
      }
      final len = int.parse(m[1]!);
      if (buf.length < sep + 4 + len) break;
      final body = utf8.decode(buf.sublist(sep + 4, sep + 4 + len));
      buf.removeRange(0, sep + 4 + len);
      final msg = jsonDecode(body);
      if (msg is Map<String, Object?>) yield msg;
    }
  }
}

int _indexOf(List<int> data, List<int> pattern) {
  outer:
  for (var i = 0; i + pattern.length <= data.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Encode un message JSON-RPC avec son en-tête.
List<int> lspFrame(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode(message));
  return [...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
}

/// Chemin local d'une URI `file://` (null : autre schéma).
String? uriToPath(String uri) {
  final u = Uri.tryParse(uri);
  return u == null || u.scheme != 'file' ? null : u.toFilePath();
}

class _Document {
  _Document(this.uri, this.path, this.text, this.languageId);
  final String uri;
  final String? path;
  String text;
  final String languageId;

  /// Incrémenté à chaque changement : un résultat plus ancien est ignoré.
  int generation = 0;

  /// Problèmes publiés (index = `data.i` des diagnostics).
  List<Finding> published = const [];

  /// Dernière analyse complète (outils externes compris).
  ScriptReport? full;

  /// Le texte est celui du fichier sur disque (ouvert ou enregistré).
  bool onDisk = true;
  Timer? typing;
}

class LspServer {
  LspServer(this._input, this._output,
      {CommandRunner runner = const ProcessCommandRunner(), Lang? lang})
      : _runner = runner,
        _lang = lang ?? Lang.fromEnvironment(Platform.environment);

  final Stream<List<int>> _input;
  final IOSink _output;
  final CommandRunner _runner;
  Lang _lang;
  Profile? _profile;
  bool _onType = true;
  Duration _typingDelay = const Duration(milliseconds: 600);

  final _docs = <String, _Document>{};
  final _engines = <String?, Engine>{};
  var _shutdown = false;

  /// Traite les messages jusqu'à `exit` ou la fin du flux ; renvoie le code
  /// de sortie (0 si `shutdown` a précédé `exit`).
  Future<int> serve() async {
    await for (final msg in lspMessages(_input)) {
      if (msg['method'] == 'exit') break;
      unawaited(_dispatch(msg));
    }
    for (final d in _docs.values) {
      d.typing?.cancel();
    }
    await _output.flush();
    return _shutdown ? 0 : 1;
  }

  void _send(Map<String, Object?> msg) =>
      _output.add(lspFrame({'jsonrpc': '2.0', ...msg}));

  void _notify(String method, Object? params) =>
      _send({'method': method, 'params': params});

  void _log(String text, {int type = 3}) =>
      _notify('window/logMessage', {'type': type, 'message': text});

  Future<void> _dispatch(Map<String, Object?> msg) async {
    final id = msg['id'];
    final method = msg['method'] as String?;
    final params = msg['params'];
    if (method == null) return; // réponse à une requête du serveur
    try {
      final result = await _handle(method, params is Map ? params : const {});
      if (id != null) _send({'id': id, 'result': result});
    } on _MethodNotFound {
      if (id != null) {
        _send({
          'id': id,
          'error': {'code': -32601, 'message': 'Unknown method: $method'}
        });
      }
    } catch (e, st) {
      _log('check-script : $method : $e\n$st', type: 1);
      if (id != null) {
        _send({
          'id': id,
          'error': {'code': -32603, 'message': '$e'}
        });
      }
    }
  }

  Future<Object?> _handle(String method, Map params) async {
    switch (method) {
      case 'initialize':
        _options(params['initializationOptions']);
        return {
          'capabilities': {
            'textDocumentSync': {
              'openClose': true,
              'change': 1, // texte complet
              'save': {'includeText': false},
            },
            'hoverProvider': true,
            'codeActionProvider': {
              'codeActionKinds': ['quickfix'],
            },
            'documentFormattingProvider': true,
            'executeCommandProvider': {
              'commands': ['check-script.analyze'],
            },
          },
          'serverInfo': {'name': 'check-script', 'version': appVersion},
        };
      case 'initialized':
        return null;
      case 'shutdown':
        _shutdown = true;
        return null;
      case 'workspace/didChangeConfiguration':
        final s = params['settings'];
        final before = _optionsKey;
        if (s is Map && s['checkScript'] != null) _options(s['checkScript']);
        // Les clients envoient leur configuration au démarrage : pas de
        // nouvelle analyse si rien n'a changé.
        if (_optionsKey == before) return null;
        _engines.clear();
        for (final d in _docs.values) {
          unawaited(_analyze(d, full: true));
        }
        return null;
      case 'textDocument/didOpen':
        final td = params['textDocument'] as Map;
        final uri = td['uri'] as String;
        final d = _Document(uri, uriToPath(uri), td['text'] as String,
            '${td['languageId'] ?? ''}');
        _docs[uri] = d;
        d.onDisk = d.path != null &&
            File(d.path!).existsSync() &&
            File(d.path!).readAsStringSync() == d.text;
        await _analyze(d, full: true);
        return null;
      case 'textDocument/didChange':
        final d = _docs[(params['textDocument'] as Map)['uri']];
        final changes = params['contentChanges'] as List;
        if (d == null || changes.isEmpty) return null;
        d.text = (changes.last as Map)['text'] as String;
        d.onDisk = false;
        d.generation++;
        d.typing?.cancel();
        if (_onType) {
          d.typing = Timer(_typingDelay, () => _analyze(d, full: false));
        }
        return null;
      case 'textDocument/didSave':
        final d = _docs[(params['textDocument'] as Map)['uri']];
        if (d == null) return null;
        if (params['text'] is String) d.text = params['text'] as String;
        d.onDisk = true;
        d.typing?.cancel();
        await _analyze(d, full: true);
        return null;
      case 'textDocument/didClose':
        final uri = (params['textDocument'] as Map)['uri'] as String;
        _docs.remove(uri)?.typing?.cancel();
        _notify('textDocument/publishDiagnostics',
            {'uri': uri, 'diagnostics': const []});
        return null;
      case 'textDocument/hover':
        return _hover(params);
      case 'textDocument/codeAction':
        return _codeActions(params);
      case 'textDocument/formatting':
        return _format(params);
      case 'workspace/executeCommand':
        final args = params['arguments'];
        final uri = args is List && args.isNotEmpty ? '${args.first}' : null;
        final d = _docs[uri];
        if (params['command'] == 'check-script.analyze' && d != null) {
          await _analyze(d, full: true);
        }
        return null;
    }
    if (method.startsWith(r'$/')) return null; // notifications facultatives
    throw _MethodNotFound();
  }

  String get _optionsKey => '$_lang|$_profile|$_onType|$_typingDelay';

  void _options(Object? o) {
    if (o is! Map) return;
    _lang = Lang.tryParse('${o['lang'] ?? ''}') ?? _lang;
    if (o['profile'] != null) _profile = Profile.tryParse('${o['profile']}');
    if (o['analyzeOnType'] is bool) _onType = o['analyzeOnType'] as bool;
    if (o['typingDelay'] is num) {
      _typingDelay = Duration(milliseconds: (o['typingDelay'] as num).toInt());
    }
  }

  // ── Analyse ───────────────────────────────────────────────────────────────

  static final _scriptExt =
      RegExp(r'\.(?:sh|bash|ksh|dash|zsh|pyw?)$', caseSensitive: false);
  static final _shebang =
      RegExp(r'^#!.*\b(?:(?:ba|da|k|mk|z)?sh|python[23]?(?:\.\d+)?)\b');

  /// Le document est un script (ou contient des scripts intégrés).
  static bool isAnalyzable(String? path, String text, String languageId) {
    if (const {'shellscript', 'sh', 'bash', 'zsh', 'python'}
        .contains(languageId)) {
      return true;
    }
    final p = path ?? '';
    return _scriptExt.hasMatch(p) ||
        _shebang.hasMatch(text.split('\n').first) ||
        detectEmbedded(p, text) != null;
  }

  CheckConfig _config(String? path) {
    final found = path == null ? null : findProjectConfig(path);
    if (found != null) {
      try {
        return CheckConfig.parse(File(found).readAsStringSync(),
            profile: _profile);
      } on Object catch (e) {
        _log('check-script : $found : $e', type: 1);
      }
    }
    return CheckConfig.forProfile(_profile ?? Profile.standard);
  }

  Engine _engine(String? path) {
    final key = path == null ? null : findProjectConfig(path);
    return _engines.putIfAbsent(
        key, () => Engine(config: _config(path), lang: _lang, runner: _runner));
  }

  /// Analyse [d] : complète (tous les outils), ou rapide pendant la frappe
  /// (règles intégrées, syntaxe, règles personnalisées).
  Future<void> _analyze(_Document d, {required bool full}) async {
    final gen = d.generation;
    if (!isAnalyzable(d.path, d.text, d.languageId)) {
      _publish(d, const []);
      return;
    }
    final base = _engine(d.path);
    final script = ScriptInfo.fromContent(d.path ?? d.uri, d.text);
    final ScriptReport report;
    try {
      if (full) {
        report = await base.analyze(script,
            filePath: d.onDisk && d.path != null ? d.path : null);
      } else {
        report = await Engine(
            config: base.config,
            lang: _lang,
            runner: _runner,
            analyzers: [
              SyntaxAnalyzer(),
              BuiltinAnalyzer(),
              CustomRulesAnalyzer(),
            ]).analyze(script);
      }
    } on Object catch (e) {
      _log('check-script : ${d.uri} : $e', type: 1);
      return;
    }
    if (_docs[d.uri] != d || d.generation != gen) return; // obsolète
    if (full) {
      d.full = report;
      _publish(d, report.findings);
      _notify('checkScript/score', {
        'uri': d.uri,
        'score': report.global,
        'grade': report.grade,
        'findings': report.findings.length,
      });
    } else {
      _publish(d, _mergeTyping(report, d.full, script));
    }
  }

  /// Pendant la frappe : problèmes rapides, plus ceux des outils externes de
  /// la dernière analyse complète dont la ligne n'a pas changé.
  static List<Finding> _mergeTyping(
      ScriptReport quick, ScriptReport? full, ScriptInfo now) {
    const quickTools = {'builtin', 'syntax', 'custom'};
    final lines = now.displayLines;
    final kept = [
      for (final f in full?.findings ?? const <Finding>[])
        if (!quickTools.contains(f.tool) &&
            (f.line == 0 ||
                (f.line <= lines.length &&
                    (f.snippet == null ||
                        lines[f.line - 1].trimRight() == f.snippet))))
          f.copyWith(edits: const []), // positions peut-être décalées
    ];
    return sortFindings(deduplicate([...kept, ...quick.findings]));
  }

  void _publish(_Document d, List<Finding> findings) {
    d.published = findings;
    final lines = ScriptInfo.fromContent(d.path ?? d.uri, d.text).displayLines;
    _notify('textDocument/publishDiagnostics', {
      'uri': d.uri,
      'diagnostics': [
        for (var i = 0; i < findings.length; i++)
          _diagnostic(findings[i], i, lines),
      ],
    });
  }

  Map<String, Object?> _diagnostic(Finding f, int index, List<String> lines) {
    final line = f.line < 1 ? 0 : f.line - 1;
    final text = line < lines.length ? lines[line] : '';
    final start = f.line < 1 || f.column < 1
        ? text.length - text.trimLeft().length
        : (f.column - 1).clamp(0, text.length);
    return {
      'range': {
        'start': {'line': line, 'character': start},
        'end': {'line': line, 'character': text.length},
      },
      'severity': switch (f.severity) {
        Severity.critical || Severity.high => 1,
        Severity.medium => 2,
        Severity.low => 3,
      },
      'code': f.ruleId,
      if (f.url != null) 'codeDescription': {'href': f.url},
      'source':
          f.tool == 'builtin' ? 'check-script' : 'check-script (${f.tool})',
      'message': f.hint == null ? f.message : '${f.message}\n→ ${f.hint}',
      'data': {'i': index},
    };
  }

  // ── Survol ────────────────────────────────────────────────────────────────

  Object? _hover(Map params) {
    final d = _docs[(params['textDocument'] as Map)['uri']];
    if (d == null) return null;
    final line = ((params['position'] as Map)['line'] as num).toInt() + 1;
    final here = [
      for (final f in d.published)
        if (f.line == line) f
    ];
    if (here.isEmpty) return null;
    final t = Messages(_lang);
    final fence = switch (
        d.full?.script ?? ScriptInfo.fromContent(d.path ?? d.uri, d.text)) {
      final s when s.embedded != null =>
        s.embedded!.kind == EmbeddedKind.dockerfile
            ? 'dockerfile'
            : (s.embedded!.kind == EmbeddedKind.makefile ? 'makefile' : 'yaml'),
      final s when s.dialect.isPython => 'python',
      _ => 'sh',
    };
    final fr = _lang == Lang.fr;
    final parts = <String>[];
    for (final f in here) {
      final b = StringBuffer(
          '**${f.ruleId}** · ${f.severity.label} · ${t.category(f.category)}'
          ' — ${f.tool}\n\n${f.message}');
      if (f.hint != null) b.write('\n\n→ ${f.hint}');
      final ex = exampleFor(f.ruleId);
      if (ex != null) {
        b.write('\n\n${fr ? 'À éviter' : 'Avoid'} :\n```$fence\n'
            '${ex.badOf(_lang)}\n```\n${fr ? 'À écrire' : 'Write'} :\n'
            '```$fence\n${ex.goodOf(_lang)}\n```');
      }
      if (f.url != null) {
        b.write('\n\n[${fr ? 'Documentation' : 'Documentation'}](${f.url})');
      }
      if (f.refs.isNotEmpty) {
        b.write('\n\n${[
          for (final r in f.refs)
            referenceUrl(r) == null ? r : '[$r](${referenceUrl(r)})'
        ].join(' · ')}');
      }
      parts.add(b.toString());
    }
    return {
      'contents': {'kind': 'markdown', 'value': parts.join('\n\n---\n\n')},
    };
  }

  // ── Corrections rapides ───────────────────────────────────────────────────

  static Map<String, Object?> _range(int l1, int c1, int l2, int c2) => {
        'start': {'line': l1, 'character': c1},
        'end': {'line': l2, 'character': c2},
      };

  static Map<String, Object?> _lspEdit(TextEdit e) => {
        'range':
            _range(e.line - 1, e.column - 1, e.endLine - 1, e.endColumn - 1),
        'newText': e.replacement,
      };

  Map<String, Object?> _action(String title, String uri, List<Object?> edits,
          {Object? diagnostic, bool preferred = false}) =>
      {
        'title': title,
        'kind': 'quickfix',
        if (diagnostic != null) 'diagnostics': [diagnostic],
        if (preferred) 'isPreferred': true,
        'edit': {
          'changes': {uri: edits}
        },
      };

  Object? _codeActions(Map params) {
    final uri = (params['textDocument'] as Map)['uri'] as String;
    final d = _docs[uri];
    if (d == null) return const [];
    final fr = _lang == Lang.fr;
    final lines = d.text.split('\n');
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final diag
        in (params['context'] as Map?)?['diagnostics'] as List? ?? const []) {
      final data = (diag as Map)['data'];
      final i = data is Map ? data['i'] : null;
      if (i is! int || i >= d.published.length) continue;
      final f = d.published[i];
      if (f.edits.isNotEmpty) {
        out.add(_action(fr ? 'Corriger : ${f.ruleId}' : 'Fix: ${f.ruleId}', uri,
            [for (final e in f.edits) _lspEdit(e)],
            diagnostic: diag, preferred: true));
        final same = [
          for (final x in d.published)
            if (x.ruleId == f.ruleId && x.edits.isNotEmpty) x
        ];
        if (same.length > 1 && seen.add('all:${f.ruleId}')) {
          out.add(_action(
              fr
                  ? 'Corriger les ${same.length} occurrences de ${f.ruleId}'
                  : 'Fix all ${same.length} occurrences of ${f.ruleId}',
              uri,
              [
                for (final x in same)
                  for (final e in x.edits) _lspEdit(e)
              ]));
        }
      }
      // Directive sur la ligne précédente (même indentation).
      if (f.line >= 1 && f.line <= lines.length) {
        final l = lines[f.line - 1];
        final indent = l.substring(0, l.length - l.trimLeft().length);
        out.add(_action(
            fr
                ? 'Ignorer ${f.ruleId} sur cette ligne'
                : 'Ignore ${f.ruleId} on this line',
            uri,
            [
              {
                'range': _range(f.line - 1, 0, f.line - 1, 0),
                'newText': '$indent# check-script disable=${f.ruleId}\n',
              }
            ],
            diagnostic: diag));
      }
      if (seen.add('file:${f.ruleId}')) {
        final at = lines.isNotEmpty && lines.first.startsWith('#!') ? 1 : 0;
        out.add(_action(
            fr
                ? 'Ignorer ${f.ruleId} dans tout le fichier'
                : 'Ignore ${f.ruleId} in the whole file',
            uri,
            [
              {
                'range': _range(at, 0, at, 0),
                'newText': '# check-script disable-file=${f.ruleId}\n',
              }
            ],
            diagnostic: diag));
      }
    }
    return out;
  }

  // ── Formatage ─────────────────────────────────────────────────────────────

  Future<Object?> _format(Map params) async {
    final d = _docs[(params['textDocument'] as Map)['uri']];
    if (d == null || !isAnalyzable(d.path, d.text, d.languageId)) return null;
    final script = ScriptInfo.fromContent(d.path ?? d.uri, d.text);
    final formatted = await formatScript(script,
        config: _engine(d.path).config, runner: _runner);
    if (formatted == null) return const [];
    final lines = d.text.split('\n');
    return [
      {
        'range': _range(0, 0, lines.length - 1, lines.last.length),
        'newText': formatted,
      }
    ];
  }
}

class _MethodNotFound implements Exception {}
