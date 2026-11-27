/// Relecture par un fournisseur **distant** : le contenu du script quitte la
/// machine, uniquement sur demande explicite de l'appelant.
///
/// Garde-fous :
/// - adresses figées, HTTPS, sans redirection : la clé d'API ne peut pas être
///   détournée vers un autre serveur ;
/// - clés lues dans l'environnement, jamais enregistrées ni affichées ;
/// - même invite et même masquage des secrets que pour le modèle local ; le
///   chemin du fichier n'est pas envoyé.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../i18n.dart';
import '../script_info.dart';
import 'anomaly.dart';
import 'local_model.dart';

/// Envoie [body] en POST à [url] et rend le corps de la réponse.
typedef RemoteTransport = Future<String> Function(
    Uri url, Map<String, String> headers, String body, Duration timeout);

const _maxOutputTokens = 16000;
const _claudeModel = 'claude-sonnet-5-5';

enum AiProvider {
  ollama('Ollama', defaultAiModel, '', ''),
  claude('Claude', _claudeModel, 'ANTHROPIC_API_KEY', 'api.anthropic.com'),
  mistral(
      'Mistral', 'mistral-medium-latest', 'MISTRAL_API_KEY', 'api.mistral.ai'),
  gemini('Gemini', 'gemini-3.8-flash', 'GEMINI_API_KEY',
      'generativelanguage.googleapis.com');

  final String label;
  final String defaultModel;
  final String keyVariable;
  final String host;
  const AiProvider(this.label, this.defaultModel, this.keyVariable, this.host);

  bool get remote => this != ollama;

  static AiProvider? tryParse(String name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

class RemoteModel implements ReviewModel {
  final AiProvider provider;
  @override
  final String model;
  final String _apiKey;
  final Duration timeout;
  final bool fast;
  final RemoteTransport transport;

  RemoteModel._(this.provider, this.model, this._apiKey, this.timeout,
      this.fast, this.transport);

  /// Lève [ModelException] si la clé manque ou si le nom du modèle est
  /// invalide. [fast] n'a d'effet que chez Claude (effort réduit).
  factory RemoteModel(AiProvider provider,
      {required String? apiKey,
      String? model,
      Duration timeout = defaultAiTimeout,
      bool fast = false,
      RemoteTransport? transport}) {
    assert(provider.remote);
    final key = apiKey?.trim() ?? '';
    if (key.isEmpty) {
      throw ModelException('${provider.keyVariable} is not set');
    }
    // Un en-tête ne doit pas pouvoir être coupé, ni la clé apparaître dans
    // l'erreur levée par le client HTTP.
    if (key.codeUnits.any((c) => c <= 0x20 || c >= 0x7F)) {
      throw ModelException(
          '${provider.keyVariable} contains invalid characters');
    }
    final name = model ?? provider.defaultModel;
    // Le nom entre dans l'URL de Gemini.
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(name)) {
      throw ModelException('invalid model name: $name');
    }
    return RemoteModel._(
        provider, name, key, timeout, fast, transport ?? _httpsPost);
  }

  @override
  Future<({List<Anomaly> anomalies, bool truncated})> review(
      ScriptInfo script, Lang lang) async {
    final prompt = buildPrompt(script, lang);
    final request = _request(prompt.text);
    final reply = await transport(Uri.https(provider.host, request.path),
        request.headers, jsonEncode(request.body), timeout);
    return (
      anomalies: parseSuggestions(_text(reply), script.totalLines),
      truncated: prompt.truncated
    );
  }

  ({String path, Map<String, String> headers, Map<String, Object?> body})
      _request(String prompt) {
    switch (provider) {
      case AiProvider.claude:
        // Le repli côté serveur n'est accepté que par certains modèles.
        final fallback = model == _claudeModel;
        return (
          path: '/v1/messages',
          headers: {
            'x-api-key': _apiKey,
            'anthropic-version': '2026-10-21',
            if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
          },
          body: {
            'model': model,
            'max_tokens': _maxOutputTokens,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'output_config': {
              if (fast) 'effort': 'low',
              'format': {'type': 'json_schema', 'schema': _schema},
            },
            if (fallback) 'fallbacks': 'default',
          },
        );
      case AiProvider.mistral:
        return (
          path: '/v1/chat/completions',
          headers: {'authorization': 'Bearer $_apiKey'},
          body: {
            'model': model,
            'max_tokens': _maxOutputTokens,
            'temperature': 0,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
          },
        );
      case AiProvider.gemini:
        return (
          path: '/v1beta/models/$model:generateContent',
          headers: {'x-goog-api-key': _apiKey},
          body: {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'responseMimeType': 'application/json',
              'maxOutputTokens': _maxOutputTokens,
            },
          },
        );
      case AiProvider.ollama:
        throw StateError('Ollama is handled by LocalModel');
    }
  }

  /// Texte produit par le modèle ; un refus ou une réponse coupée lève
  /// [ModelException] pour ne pas passer pour une absence de défaut.
  String _text(String reply) {
    Object? doc;
    try {
      doc = jsonDecode(reply);
    } on FormatException {
      doc = null;
    }
    if (doc is! Map) {
      throw const ModelException('unreadable reply (JSON expected)');
    }
    final String? text;
    switch (provider) {
      case AiProvider.claude:
        _checkStop(doc['stop_reason'],
            ok: const ['end_turn', 'stop_sequence'], cut: 'max_tokens');
        text = _joinText(doc['content'], (b) => b['type'] == 'text');
      case AiProvider.mistral:
        final choice = _first(doc['choices']);
        _checkStop(choice?['finish_reason'], ok: const ['stop'], cut: 'length');
        final message = choice?['message'];
        final content = message is Map ? message['content'] : null;
        text = content is String
            ? content
            : _joinText(content, (b) => b['type'] == 'text');
      case AiProvider.gemini:
        final feedback = doc['promptFeedback'];
        final blocked = feedback is Map ? feedback['blockReason'] : null;
        if (blocked != null) {
          throw ModelException(
              'refused by the provider (${cleanModelText('$blocked', 40)})');
        }
        final candidate = _first(doc['candidates']);
        _checkStop(candidate?['finishReason'],
            ok: const ['STOP'], cut: 'MAX_TOKENS');
        final content = candidate?['content'];
        text = _joinText(content is Map ? content['parts'] : null,
            (b) => b['thought'] != true);
      case AiProvider.ollama:
        text = null;
    }
    if (text == null || text.isEmpty) {
      throw const ModelException('empty reply');
    }
    return text;
  }

  void _checkStop(Object? reason,
      {required List<String> ok, required String cut}) {
    if (ok.contains(reason)) return;
    if (reason == cut) {
      throw const ModelException('reply cut off (output limit reached)');
    }
    throw ModelException(
        'refused or interrupted (${cleanModelText('$reason', 40)})');
  }

  static Map<Object?, Object?>? _first(Object? list) =>
      list is List && list.isNotEmpty && list.first is Map
          ? list.first as Map
          : null;

  static String? _joinText(Object? blocks, bool Function(Map) keep) {
    if (blocks is! List) return null;
    return [
      for (final b in blocks.whereType<Map>())
        if (keep(b) && b['text'] is String) b['text'] as String
    ].join();
  }
}

const _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['anomalies'],
  'properties': {
    'anomalies': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['line', 'level', 'title', 'explanation'],
        'properties': {
          'line': {'type': 'integer'},
          'level': {
            'type': 'string',
            'enum': ['high', 'medium', 'low']
          },
          'title': {'type': 'string'},
          'explanation': {'type': 'string'},
        },
      },
    },
  },
};

/// Le proxy de l'environnement est respecté (accès Internet d'entreprise) : il
/// ne voit qu'un tunnel TLS.
Future<String> _httpsPost(
    Uri url, Map<String, String> headers, String body, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    Future<String> send() async {
      final req = await client.postUrl(url);
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      headers.forEach(req.headers.set);
      req.add(utf8.encode(body));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode != 200) {
        throw ModelException(httpError(res.statusCode, text),
            fatal: const [401, 402, 403, 404, 429].contains(res.statusCode));
      }
      return text;
    }

    return await send().timeout(timeout);
  } on TimeoutException {
    throw ModelException('timeout after ${timeout.inSeconds} s');
  } on SocketException catch (e) {
    throw ModelException(
        'unreachable (${e.osError?.message ?? e.message}): ${url.host}');
  } on TlsException catch (e) {
    throw ModelException('TLS error: ${e.message}');
  } on HttpException catch (e) {
    throw ModelException(e.message);
  } finally {
    client.close(force: true);
  }
}

/// Message d'erreur d'un code HTTP. Le corps de la réponse n'est repris que
/// s'il ne peut pas citer la clé (jamais pour 401 et 403).
String httpError(int status, String body) {
  final hint = switch (status) {
    401 || 403 => 'API key refused',
    404 => 'unknown model or address',
    429 => 'rate limit or quota reached',
    >= 500 => 'provider unavailable',
    _ => null,
  };
  if (status == 401 || status == 403) return 'HTTP $status: $hint';
  String? detail;
  try {
    final doc = jsonDecode(body);
    final error = doc is Map ? doc['error'] : null;
    final message =
        error is Map ? error['message'] : (doc is Map ? doc['message'] : null);
    if (message is String) {
      detail = maskSecrets([cleanModelText(message, 200)]).single;
    }
  } on FormatException {
    detail = null;
  }
  return ['HTTP $status', if (hint != null) hint, if (detail != null) detail]
      .join(': ');
}
