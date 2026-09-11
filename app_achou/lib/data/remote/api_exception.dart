/// Erro vindo da API, já traduzido do envelope `{ error: { code, message } }`.
///
/// A UI mostra [message] ao usuário e usa [code] quando precisa reagir a um
/// caso específico (token expirado, estoque insuficiente).
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.cause,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Object? cause;

  bool get semConexao => code == 'SEM_CONEXAO';
  bool get naoAutorizado => statusCode == 401;

  @override
  String toString() => 'ApiException($code): $message';
}
