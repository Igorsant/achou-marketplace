import '../models/category.dart';
import '../models/product.dart';
import '../remote/api_client.dart';
import 'product_repository.dart';

/// Catálogo servido por `GET /v1/products`.
class HttpProductRepository implements ProductRepository {
  const HttpProductRepository(this._api);

  final ApiClient _api;

  static const int _limiteRelacionados = 6;

  /// Fixo porque `GET /v1/categories` não existe no backend. Os slugs são os
  /// do seed (`prisma/seed.ts`) — quando a rota existir, isto sai daqui.
  static const List<Category> _categoriasDoSeed = <Category>[
    Category.todas,
    Category(name: 'Calçados', slug: 'calcados'),
    Category(name: 'Vestuário', slug: 'vestuario'),
    Category(name: 'Acessórios', slug: 'acessorios'),
  ];

  @override
  List<Category> categories() => _categoriasDoSeed;

  @override
  Future<ProductPage> search({
    String? term,
    String? categorySlug,
    int page = 1,
    int limit = 20,
  }) async {
    final Map<String, dynamic> corpo = await _api.getObject(
      '/v1/products',
      query: <String, String>{
        if (term != null && term.trim().isNotEmpty) 'q': term.trim(),
        if (categorySlug != null && categorySlug.isNotEmpty)
          'category': categorySlug,
        'page': '$page',
        'limit': '$limit',
      },
    );

    return ProductPage.fromJson(corpo);
  }

  @override
  Future<ProductDetails> details(String id) async {
    final Map<String, dynamic> corpo = await _api.getObject('/v1/products/$id');
    final Product product = Product.fromJson(corpo);

    return ProductDetails(
      product: product,
      related: await _relacionados(product),
    );
  }

  /// Não há rota de relacionados: reaproveita a listagem filtrando pela mesma
  /// categoria. Falha aqui não derruba o detalhe — a faixa simplesmente some.
  Future<List<Product>> _relacionados(Product product) async {
    if (product.categorySlug.isEmpty) {
      return const <Product>[];
    }

    try {
      final ProductPage pagina = await search(
        categorySlug: product.categorySlug,
        limit: _limiteRelacionados + 1,
      );
      return pagina.items
          .where((Product outro) => outro.id != product.id)
          .take(_limiteRelacionados)
          .toList();
    } on Object {
      return const <Product>[];
    }
  }
}
