import '../models/category.dart';
import '../models/product.dart';

/// Uma página de resultados do catálogo, no formato que a API devolve.
class ProductPage {
  const ProductPage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  const ProductPage.single(this.items)
      : page = 1,
        totalPages = 1,
        total = -1;

  final List<Product> items;
  final int page;
  final int totalPages;
  final int total;

  bool get temProximaPagina => page < totalPages;

  factory ProductPage.fromJson(Map<String, dynamic> json) {
    final List<dynamic> data = json['data'] as List<dynamic>? ?? <dynamic>[];
    final Map<String, dynamic> paginacao =
        json['pagination'] as Map<String, dynamic>? ?? <String, dynamic>{};

    return ProductPage(
      items: data
          .map((dynamic item) =>
              Product.fromJson(item as Map<String, dynamic>))
          .toList(),
      page: paginacao['page'] as int? ?? 1,
      totalPages: paginacao['totalPages'] as int? ?? 1,
      total: paginacao['total'] as int? ?? data.length,
    );
  }
}

/// Produto completo mais a vitrine de relacionados, resolvidos juntos para que
/// a tela de detalhe espere por um único `Future`.
class ProductDetails {
  const ProductDetails({required this.product, required this.related});

  final Product product;
  final List<Product> related;
}

/// Contrato que as telas enxergam. Existem duas implementações:
/// [MockProductRepository], em memória, e [HttpProductRepository], na API.
abstract class ProductRepository {
  Future<ProductPage> search({
    String? term,
    String? categorySlug,
    int page = 1,
    int limit = 20,
  });

  Future<ProductDetails> details(String id);

  /// Síncrono de propósito: `GET /v1/categories` não existe no backend, então
  /// hoje as duas implementações devolvem uma lista fixa. Quando a rota
  /// aparecer, isto vira `Future`.
  List<Category> categories();
}
