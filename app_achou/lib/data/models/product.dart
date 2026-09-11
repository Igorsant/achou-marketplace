/// Produto do catálogo.
///
/// Os nomes seguem o contrato da API (`title`, `priceCents`) para que o
/// [Product.fromJson] seja tradução direta, sem apelido no meio.
class Product {
  const Product({
    required this.id,
    required this.title,
    required this.category,
    required this.categorySlug,
    required this.seller,
    required this.priceCents,
    this.compareAtPriceCents,
    this.description = '',
    this.imageUrl = '',
    this.inStock = true,
    this.stock,
    this.status = 'ACTIVE',
    this.warrantyMonths = 12,
  });

  final String id;
  final String title;

  /// Nome exibível da categoria. A listagem da API não devolve categoria —
  /// só o detalhe — então vem vazio em produtos vindos de `GET /v1/products`.
  final String category;
  final String categorySlug;

  final String seller;

  /// Preço em centavos. Nunca `double`: soma de dinheiro em ponto flutuante
  /// acumula erro de arredondamento.
  final int priceCents;

  /// Preço anterior, quando o produto está em promoção. Ainda não existe no
  /// backend — depende da coluna `compare_at_price_cents`.
  final int? compareAtPriceCents;

  final String description;
  final String imageUrl;
  final bool inStock;

  /// Quantidade exata. Só vem nas rotas do lojista e no detalhe — a listagem
  /// pública devolve apenas `inStock`.
  final int? stock;

  /// `ACTIVE`, `INACTIVE` ou `ARCHIVED`. Só as rotas do lojista devolvem: a
  /// listagem pública já filtra por ativos.
  final String status;

  final int warrantyMonths;

  bool get isArchived => status == 'ARCHIVED';

  Product copyWith({
    String? title,
    int? priceCents,
    String? description,
    String? imageUrl,
    int? stock,
    String? status,
  }) {
    return Product(
      id: id,
      title: title ?? this.title,
      category: category,
      categorySlug: categorySlug,
      seller: seller,
      priceCents: priceCents ?? this.priceCents,
      compareAtPriceCents: compareAtPriceCents,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      inStock: (stock ?? this.stock ?? 1) > 0,
      stock: stock ?? this.stock,
      status: status ?? this.status,
      warrantyMonths: warrantyMonths,
    );
  }

  bool get hasDiscount =>
      compareAtPriceCents != null && compareAtPriceCents! > priceCents;

  int get discountPercent {
    if (!hasDiscount) {
      return 0;
    }
    final int desconto = compareAtPriceCents! - priceCents;
    return ((desconto / compareAtPriceCents!) * 100).round();
  }

  /// Aceita os dois formatos que a API devolve: o resumido da listagem
  /// (`id`, `title`, `priceCents`, `imageUrl`, `inStock`, `seller`) e o
  /// completo do detalhe, que traz `description`, `stock` e `category`.
  factory Product.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? seller =
        json['seller'] as Map<String, dynamic>?;
    final Map<String, dynamic>? category =
        json['category'] as Map<String, dynamic>?;
    final int? stock = json['stock'] as int?;

    return Product(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      category: category?['name'] as String? ?? '',
      categorySlug: category?['slug'] as String? ?? '',
      seller: seller?['storeName'] as String? ?? '',
      priceCents: json['priceCents'] as int? ?? 0,
      compareAtPriceCents: json['compareAtPriceCents'] as int?,
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      inStock: json['inStock'] as bool? ?? (stock ?? 0) > 0,
      stock: stock,
      status: json['status'] as String? ?? 'ACTIVE',
    );
  }
}
