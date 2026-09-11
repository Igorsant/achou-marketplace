import 'package:flutter/widgets.dart';

import '../data/models/session.dart';
import '../data/remote/api_exception.dart';
import '../data/repositories/auth_repository.dart';

/// Sessão do lojista. Vive em memória: fechou o app, precisa entrar de novo.
/// Persistir o refresh token é assunto para quando houver onde guardá-lo com
/// segurança (Keychain / Keystore), não `SharedPreferences`.
class SessionController extends ChangeNotifier {
  SessionController(this._auth);

  final AuthRepository _auth;

  Session? _session;
  bool _ocupado = false;
  String? _erro;

  Session? get session => _session;
  bool get autenticado => _session != null;
  bool get ocupado => _ocupado;
  String? get erro => _erro;
  String? get token => _session?.accessToken;

  Future<bool> signIn({
    required String email,
    required String password,
  }) {
    return _tentar(() => _auth.signIn(email: email, password: password));
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    required String storeName,
  }) {
    return _tentar(() => _auth.signUp(
          name: name,
          email: email,
          password: password,
          storeName: storeName,
        ));
  }

  /// Chamado quando a API responde 401: o access token dura 15 minutos e o
  /// refresh, 7 dias. Renovando em silêncio, o lojista não é jogado de volta
  /// para o login no meio de um cadastro.
  Future<bool> renovar() async {
    final String? refreshToken = _session?.refreshToken;
    if (refreshToken == null) {
      return false;
    }

    try {
      _session = await _auth.refresh(refreshToken);
      notifyListeners();
      return true;
    } on ApiException {
      // Refresh vencido ou inválido: aí sim a sessão acabou.
      signOut();
      return false;
    }
  }

  void signOut() {
    _session = null;
    _erro = null;
    notifyListeners();
  }

  Future<bool> _tentar(Future<Session> Function() acao) async {
    _ocupado = true;
    _erro = null;
    notifyListeners();

    try {
      final Session sessao = await acao();

      // O painel é do lojista. Um comprador autentica sem erro, mas receberia
      // 403 na primeira chamada de `/v1/seller/*` — melhor barrar aqui.
      if (!sessao.isLojista) {
        _erro = 'Esta conta não é de lojista.';
        return false;
      }

      _session = sessao;
      return true;
    } on ApiException catch (erro) {
      _erro = erro.message;
      return false;
    } finally {
      _ocupado = false;
      notifyListeners();
    }
  }
}

class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({
    super.key,
    required SessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static SessionController of(BuildContext context) {
    final SessionScope? scope =
        context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope não encontrado acima deste widget.');
    return scope!.notifier!;
  }
}
