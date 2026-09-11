import '../models/session.dart';
import '../remote/api_client.dart';

abstract class AuthRepository {
  Future<Session> signIn({required String email, required String password});

  Future<Session> signUp({
    required String name,
    required String email,
    required String password,
    required String storeName,
  });

  /// Troca o refresh token (7 dias) por um par novo de tokens.
  Future<Session> refresh(String refreshToken);
}

class HttpAuthRepository implements AuthRepository {
  const HttpAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<Session> signIn({
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> corpo = await _api.postObject(
      '/v1/auth/login',
      body: <String, String>{'email': email, 'password': password},
    );
    return Session.fromJson(corpo);
  }

  @override
  Future<Session> signUp({
    required String name,
    required String email,
    required String password,
    required String storeName,
  }) async {
    final Map<String, dynamic> corpo = await _api.postObject(
      '/v1/auth/register',
      body: <String, String>{
        'name': name,
        'email': email,
        'password': password,
        // Só existe cadastro de lojista no app: o comprador não precisa de
        // conta enquanto não há carrinho no servidor.
        'role': 'LOJISTA',
        'storeName': storeName,
      },
    );
    return Session.fromJson(corpo);
  }

  @override
  Future<Session> refresh(String refreshToken) async {
    final Map<String, dynamic> corpo = await _api.postObject(
      '/v1/auth/refresh',
      body: <String, String>{'refreshToken': refreshToken},
    );
    return Session.fromJson(corpo);
  }
}

/// Sessão de faz de conta para o modo mockado: aceita qualquer credencial.
class MockAuthRepository implements AuthRepository {
  const MockAuthRepository();

  static const Session _sessao = Session(
    accessToken: 'mock',
    refreshToken: 'mock',
    userName: 'TechStore SP',
    role: 'LOJISTA',
    sellerId: 'mock-seller',
  );

  @override
  Future<Session> signIn({
    required String email,
    required String password,
  }) async =>
      _sessao;

  @override
  Future<Session> signUp({
    required String name,
    required String email,
    required String password,
    required String storeName,
  }) async =>
      Session(
        accessToken: 'mock',
        refreshToken: 'mock',
        userName: storeName,
        role: 'LOJISTA',
        sellerId: 'mock-seller',
      );

  @override
  Future<Session> refresh(String refreshToken) async => _sessao;
}
