import '../models/category.dart';
import '../models/product.dart';

/// Catálogo fictício. Preços em centavos, igual ao backend.
class MockProducts {
  MockProducts._();

  static const String sellerName = 'TechStore SP';

  static const List<Category> categories = <Category>[
    Category.todas,
    Category(name: 'Áudio', slug: 'audio'),
    Category(name: 'Games', slug: 'games'),
    Category(name: 'Celulares', slug: 'celulares'),
    Category(name: 'Computadores', slug: 'computadores'),
  ];

  static const List<Product> all = <Product>[
    Product(
      id: 'p1',
      title: 'Headphone Bluetooth ANC',
      category: 'Áudio',
      categorySlug: 'audio',
      seller: 'SomLivre Áudio',
      priceCents: 64900,
      compareAtPriceCents: 109900,
      description:
          'Cancelamento de ruído ativo, 40h de bateria. Frete grátis acima de '
          'R\$299 e envio para todo o Brasil.',
    ),
    Product(
      id: 'p2',
      title: 'Fones In-Ear TWS Pro',
      category: 'Áudio',
      categorySlug: 'audio',
      seller: 'SomLivre Áudio',
      priceCents: 28900,
      compareAtPriceCents: 49900,
      description:
          'Estojo com carregamento rápido, resistência à água IPX5 e modo '
          'ambiente.',
    ),
    Product(
      id: 'p3',
      title: 'Console Portátil 512GB',
      category: 'Games',
      categorySlug: 'games',
      seller: 'GameON Store',
      priceCents: 249900,
      compareAtPriceCents: 329900,
      description:
          'Tela OLED de 7 polegadas, 512GB de armazenamento e dois controles '
          'destacáveis.',
    ),
    Product(
      id: 'p4',
      title: 'Mouse Gamer 26K DPI',
      category: 'Games',
      categorySlug: 'games',
      seller: 'GameON Store',
      priceCents: 24900,
      compareAtPriceCents: 39900,
      description: 'Sensor óptico de 26.000 DPI, 8 botões programáveis e RGB.',
    ),
    Product(
      id: 'p5',
      title: 'Smartphone 5G 256GB',
      category: 'Celulares',
      categorySlug: 'celulares',
      seller: sellerName,
      priceCents: 269900,
      description:
          'Tela AMOLED 120Hz, câmera tripla de 50MP e carregamento rápido de '
          '67W.',
    ),
    Product(
      id: 'p6',
      title: 'Smartphone Compacto 128GB',
      category: 'Celulares',
      categorySlug: 'celulares',
      seller: sellerName,
      priceCents: 189900,
      description: 'Tela de 6,1 polegadas, bateria de 4.500mAh e NFC.',
    ),
    Product(
      id: 'p7',
      title: 'Notebook Ultrafino 14”',
      category: 'Computadores',
      categorySlug: 'computadores',
      seller: sellerName,
      priceCents: 449900,
      description: 'Processador de 12 núcleos, 16GB de RAM e SSD de 512GB.',
    ),
    Product(
      id: 'p8',
      title: 'Notebook Gamer 16” RTX',
      category: 'Computadores',
      categorySlug: 'computadores',
      seller: sellerName,
      priceCents: 699000,
      description: 'Placa dedicada RTX, tela 165Hz e teclado mecânico RGB.',
    ),
    Product(
      id: 'p9',
      title: 'Smartwatch GPS 45mm',
      category: 'Wearables',
      categorySlug: 'wearables',
      seller: sellerName,
      priceCents: 114900,
      description: 'GPS integrado, monitor de atividades e 7 dias de bateria.',
    ),
    Product(
      id: 'p10',
      title: 'Caixa de Som Portátil',
      category: 'Áudio',
      categorySlug: 'audio',
      seller: 'SomLivre Áudio',
      priceCents: 39900,
      compareAtPriceCents: 54900,
      description: 'Som 360°, 20h de reprodução e resistência à água IPX7.',
    ),
  ];

  /// Catálogo do vendedor logado no painel.
  static List<Product> get sellerCatalog =>
      all.where((Product product) => product.seller == sellerName).toList();

  static Product byId(String id) =>
      all.firstWhere((Product product) => product.id == id);

  static List<Product> byCategorySlug(String slug) {
    if (slug.isEmpty) {
      return all;
    }
    return all.where((Product product) => product.categorySlug == slug).toList();
  }

  static List<Product> search(String term) {
    final String alvo = term.trim().toLowerCase();
    if (alvo.isEmpty) {
      return all;
    }
    return all
        .where((Product product) =>
            product.title.toLowerCase().contains(alvo) ||
            product.category.toLowerCase().contains(alvo) ||
            product.seller.toLowerCase().contains(alvo))
        .toList();
  }
}
