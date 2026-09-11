import '../models/product.dart';
import '../models/seller_order.dart';

/// Tudo que o painel do lojista mostra de uma vez.
class SellerDashboard {
  const SellerDashboard({
    required this.storeName,
    required this.products,
    required this.orders,
  });

  final String storeName;
  final List<Product> products;
  final List<SellerOrder> orders;

  /// A rota do lojista devolve os arquivados junto; estes são os que o
  /// comprador enxerga na vitrine.
  List<Product> get activeProducts =>
      products.where((Product product) => !product.isArchived).toList();

  /// Soma dos pedidos recebidos. Enquanto `/v1/orders` não existir, nenhum
  /// pedido é criado e isto fica em zero — igual ao mockup.
  int get revenueCents => orders.fold(
        0,
        (int total, SellerOrder order) => total + order.subtotalCents,
      );
}

/// Dados de um produto novo. Sem `categoryId`: a API exige UUID de categoria
/// e não existe rota que liste as categorias com seus ids.
class NewProductDraft {
  const NewProductDraft({
    required this.title,
    required this.priceCents,
    required this.stock,
    this.description,
    this.imageUrl,
  });

  final String title;
  final int priceCents;
  final int stock;
  final String? description;

  /// A API valida com `@IsUrl()` e recusa o produto inteiro se o link for
  /// inválido — por isso vai só quando tem conteúdo.
  final String? imageUrl;

  Map<String, Object> toJson() {
    return <String, Object>{
      'title': title,
      'priceCents': priceCents,
      'stock': stock,
      if (description != null && description!.trim().isNotEmpty)
        'description': description!.trim(),
      if (imageUrl != null && imageUrl!.trim().isNotEmpty)
        'imageUrl': imageUrl!.trim(),
    };
  }
}

abstract class SellerRepository {
  Future<SellerDashboard> dashboard();

  Future<void> createProduct(NewProductDraft draft);

  Future<void> updateProduct(String productId, NewProductDraft draft);

  /// Rota dedicada (`PATCH .../stock`), separada da edição porque ajustar
  /// estoque é a operação que mais acontece e não deve exigir o resto.
  Future<void> updateStock(String productId, int stock);

  /// Soft delete: o produto sai da vitrine mas continua no catálogo do
  /// lojista, porque `order_items` referencia o id e apagar de verdade
  /// quebraria o histórico de pedidos.
  Future<void> archiveProduct(String productId);

  /// Desfaz o arquivamento (`PATCH` com `status: ACTIVE`).
  Future<void> restoreProduct(String productId);
}
