import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

/// Transporte HTTP da API. Só cuida de URL, cabeçalho, timeout e tradução de
/// erro — nada de regra de negócio, que fica nos repositórios.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 10);

  String get baseUrl => _baseUrl;

  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, String>? query,
    String? token,
  }) async {
    return _comoObjeto(await _send('GET', path, query: query, token: token));
  }

  Future<List<dynamic>> getArray(
    String path, {
    Map<String, String>? query,
    String? token,
  }) async {
    return _comoLista(await _send('GET', path, query: query, token: token));
  }

  Future<Map<String, dynamic>> postObject(
    String path, {
    Object? body,
    String? token,
  }) async {
    return _comoObjeto(await _send('POST', path, body: body, token: token));
  }

  Future<Map<String, dynamic>> patchObject(
    String path, {
    Object? body,
    String? token,
  }) async {
    return _comoObjeto(await _send('PATCH', path, body: body, token: token));
  }

  Future<void> delete(String path, {String? token}) async {
    await _send('DELETE', path, token: token);
  }

  Future<Object?> _send(
    String metodo,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? token,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    final Map<String, String> headers = _cabecalhos(token, temCorpo: body != null);
    final String? payload = body == null ? null : jsonEncode(body);

    http.Response resposta;
    try {
      resposta = await _executar(metodo, uri, headers, payload).timeout(_timeout);
    } on Object catch (erro) {
      // Timeout, DNS, conexão recusada, CORS no web: tudo vira o mesmo caso
      // para a UI — a API não respondeu.
      throw ApiException(
        code: 'SEM_CONEXAO',
        message: 'Não consegui falar com a API em $_baseUrl.',
        cause: erro,
      );
    }

    return _decodificar(resposta);
  }

  Future<http.Response> _executar(
    String metodo,
    Uri uri,
    Map<String, String> headers,
    String? payload,
  ) {
    switch (metodo) {
      case 'POST':
        return _client.post(uri, headers: headers, body: payload);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: payload);
      case 'DELETE':
        return _client.delete(uri, headers: headers);
      default:
        return _client.get(uri, headers: headers);
    }
  }

  Map<String, String> _cabecalhos(String? token, {required bool temCorpo}) {
    return <String, String>{
      'Accept': 'application/json',
      if (temCorpo) 'Content-Type': 'application/json; charset=utf-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Object? _decodificar(http.Response resposta) {
    final Object? corpo = resposta.body.isEmpty
        ? null
        : jsonDecode(utf8.decode(resposta.bodyBytes));

    if (resposta.statusCode >= 400) {
      throw _erroDoCorpo(corpo, resposta.statusCode);
    }
    return corpo;
  }

  /// Extrai `{ error: { code, message } }`. Quando o corpo não segue o
  /// envelope (um 502 do proxy, por exemplo), cai num erro genérico.
  ApiException _erroDoCorpo(Object? corpo, int statusCode) {
    if (corpo is Map<String, dynamic>) {
      final Object? erro = corpo['error'];
      if (erro is Map<String, dynamic>) {
        return ApiException(
          code: erro['code'] as String? ?? 'ERRO_DESCONHECIDO',
          message: erro['message'] as String? ?? 'A API recusou a requisição.',
          statusCode: statusCode,
        );
      }
      // ValidationPipe do Nest responde {message: [...], statusCode}.
      final Object? message = corpo['message'];
      if (message != null) {
        return ApiException(
          code: 'VALIDACAO',
          message: message is List<dynamic> ? message.join('\n') : '$message',
          statusCode: statusCode,
        );
      }
    }
    return ApiException(
      code: 'ERRO_HTTP_$statusCode',
      message: 'A API respondeu com status $statusCode.',
      statusCode: statusCode,
    );
  }

  Map<String, dynamic> _comoObjeto(Object? corpo) {
    if (corpo is! Map<String, dynamic>) {
      throw const ApiException(
        code: 'RESPOSTA_INESPERADA',
        message: 'A API devolveu um formato que o app não reconhece.',
      );
    }
    return corpo;
  }

  List<dynamic> _comoLista(Object? corpo) {
    if (corpo is! List<dynamic>) {
      throw const ApiException(
        code: 'RESPOSTA_INESPERADA',
        message: 'A API devolveu um formato que o app não reconhece.',
      );
    }
    return corpo;
  }
}
