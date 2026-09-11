import '../models/product.dart';
import '../models/seller_order.dart';
import '../remote/api_client.dart';
import '../remote/api_exception.dart';
import 'seller_repository.dart';

/// Devolve o token da sessão atual, ou `null` se ninguém entrou.
typedef TokenProvider = String? Function();

/// Tenta renovar a sessão. `true` significa que há um token novo para usar.
typedef SessionRefresher = Future<bool> Function();

/// Painel do lojista sobre `/v1/seller/*`.
///
/// O repositório não conhece a tela de login: recebe de fora como obter o
/// token e como renová-lo.
class HttpSellerRepository implements SellerRepository {
  const HttpSellerRepository({
    required this.api,
    required this.token,
    required this.refresh,
  });

  final ApiClient api;
  final TokenProvider token;
  final SessionRefresher refresh;

  @override
  Future<SellerDashboard> dashboard() async {
    final List<dynamic> produtos = await _autenticado(
      (String bearer) => api.getArray('/v1/seller/products', token: bearer),
    );
    final List<dynamic> pedidos = await _autenticado(
      (String bearer) => api.getArray('/v1/seller/orders', token: bearer),
    );

    return SellerDashboard(
      // O nome da loja vem da sessão, não desta rota: a tela preenche.
      storeName: '',
      products: produtos
          .map((dynamic item) => Product.fromJson(item as Map<String, dynamic>))
          .toList(),
      orders: pedidos
          .map((dynamic item) =>
              SellerOrder.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> createProduct(NewProductDraft draft) async {
    await _autenticado(
      (String bearer) => api.postObject(
        '/v1/seller/products',
        body: draft.toJson(),
        token: bearer,
      ),
    );
  }

  @override
  Future<void> updateProduct(String productId, NewProductDraft draft) async {
    await _autenticado(
      (String bearer) => api.patchObject(
        '/v1/seller/products/$productId',
        body: draft.toJson(),
        token: bearer,
      ),
    );
  }

  @override
  Future<void> updateStock(String productId, int stock) async {
    await _autenticado(
      (String bearer) => api.patchObject(
        '/v1/seller/products/$productId/stock',
        body: <String, int>{'stock': stock},
        token: bearer,
      ),
    );
  }

  @override
  Future<void> archiveProduct(String productId) async {
    await _autenticado(
      (String bearer) =>
          api.delete('/v1/seller/products/$productId', token: bearer),
    );
  }

  @override
  Future<void> restoreProduct(String productId) async {
    await _autenticado(
      (String bearer) => api.patchObject(
        '/v1/seller/products/$productId',
        body: <String, String>{'status': 'ACTIVE'},
        token: bearer,
      ),
    );
  }

  /// Um 401 significa access token vencido (dura 15min). Tenta renovar uma
  /// vez com o refresh token e repete a chamada; se a renovação falhar, o
  /// erro sobe e a sessão já foi encerrada por quem cuida dela.
  Future<T> _autenticado<T>(Future<T> Function(String bearer) acao) async {
    final String? bearer = token();
    if (bearer == null) {
      throw const ApiException(
        code: 'SEM_SESSAO',
        message: 'Entre com sua conta de lojista para ver o painel.',
        statusCode: 401,
      );
    }

    try {
      return await acao(bearer);
    } on ApiException catch (erro) {
      if (!erro.naoAutorizado) {
        rethrow;
      }

      final bool renovou = await refresh();
      final String? novoToken = token();
      if (!renovou || novoToken == null) {
        rethrow;
      }
      return acao(novoToken);
    }
  }
}
