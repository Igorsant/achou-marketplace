import '../mock/mock_products.dart';
import '../models/product.dart';
import '../models/seller_order.dart';
import 'seller_repository.dart';

/// Painel do lojista em memória. O que for cadastrado vive até o app fechar.
class MockSellerRepository implements SellerRepository {
  MockSellerRepository({this.latency = const Duration(milliseconds: 120)});

  final Duration latency;

  final List<Product> _catalogo = List<Product>.from(MockProducts.sellerCatalog);
  int _proximoId = 1000;

  @override
  Future<SellerDashboard> dashboard() async {
    await Future<void>.delayed(latency);
    return SellerDashboard(
      storeName: MockProducts.sellerName,
      products: List<Product>.unmodifiable(_catalogo),
      orders: const <SellerOrder>[],
    );
  }

  @override
  Future<void> createProduct(NewProductDraft draft) async {
    await Future<void>.delayed(latency);
    _catalogo.insert(
      0,
      Product(
        id: 'local-${_proximoId++}',
        title: draft.title,
        category: '',
        categorySlug: '',
        seller: MockProducts.sellerName,
        priceCents: draft.priceCents,
        description: draft.description ?? '',
        imageUrl: draft.imageUrl?.trim() ?? '',
        stock: draft.stock,
        inStock: draft.stock > 0,
      ),
    );
  }

  @override
  Future<void> updateProduct(String productId, NewProductDraft draft) async {
    await Future<void>.delayed(latency);
    final int index = _indice(productId);
    if (index == -1) {
      return;
    }
    _catalogo[index] = _catalogo[index].copyWith(
      title: draft.title,
      priceCents: draft.priceCents,
      stock: draft.stock,
      description: draft.description,
      imageUrl: draft.imageUrl,
    );
  }

  @override
  Future<void> updateStock(String productId, int stock) async {
    await Future<void>.delayed(latency);
    final int index = _indice(productId);
    if (index == -1) {
      return;
    }
    _catalogo[index] = _catalogo[index].copyWith(stock: stock);
  }

  /// Marca em vez de remover, como o backend: o produto continua na lista do
  /// lojista, só que arquivado.
  @override
  Future<void> archiveProduct(String productId) async {
    await Future<void>.delayed(latency);
    _mudarStatus(productId, 'ARCHIVED');
  }

  @override
  Future<void> restoreProduct(String productId) async {
    await Future<void>.delayed(latency);
    _mudarStatus(productId, 'ACTIVE');
  }

  void _mudarStatus(String productId, String status) {
    final int index = _indice(productId);
    if (index == -1) {
      return;
    }
    _catalogo[index] = _catalogo[index].copyWith(status: status);
  }

  int _indice(String productId) =>
      _catalogo.indexWhere((Product product) => product.id == productId);
}
