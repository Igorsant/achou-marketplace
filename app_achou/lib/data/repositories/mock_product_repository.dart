import '../mock/mock_products.dart';
import '../models/category.dart';
import '../models/product.dart';
import 'product_repository.dart';

/// Catálogo em memória. É o que roda quando o app sobe sem `--dart-define`.
///
/// A latência artificial não é enfeite: sem ela os estados de carregamento
/// nunca aparecem em desenvolvimento e só quebram contra a API real.
class MockProductRepository implements ProductRepository {
  const MockProductRepository({this.latency = const Duration(milliseconds: 120)});

  final Duration latency;

  @override
  List<Category> categories() => MockProducts.categories;

  @override
  Future<ProductPage> search({
    String? term,
    String? categorySlug,
    int page = 1,
    int limit = 20,
  }) async {
    await Future<void>.delayed(latency);

    List<Product> resultado = MockProducts.byCategorySlug(categorySlug ?? '');
    if (term != null && term.trim().isNotEmpty) {
      final Set<String> daBusca =
          MockProducts.search(term).map((Product p) => p.id).toSet();
      resultado =
          resultado.where((Product p) => daBusca.contains(p.id)).toList();
    }

    return ProductPage.single(resultado);
  }

  @override
  Future<ProductDetails> details(String id) async {
    await Future<void>.delayed(latency);

    final Product product = MockProducts.byId(id);
    final List<Product> related = MockProducts.all
        .where((Product other) =>
            other.categorySlug == product.categorySlug && other.id != id)
        .toList();

    return ProductDetails(product: product, related: related);
  }
}
