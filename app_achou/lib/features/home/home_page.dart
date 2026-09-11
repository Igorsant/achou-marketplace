import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/product_card.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/section_title.dart';
import '../../state/app_scope.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_signal.dart';
import '../product/product_detail_page.dart';
import 'widgets/category_tabs.dart';
import 'widgets/promo_banner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenCart});

  final VoidCallback onOpenCart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ProductRepository _repository;
  late final List<Category> _categories;
  CatalogSignal? _catalogo;
  Category _selected = Category.todas;
  Future<ProductPage>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) {
      return;
    }
    final AppDependencies deps = AppScope.of(context);
    _repository = deps.products;
    _categories = _repository.categories();
    _catalogo = deps.catalog..addListener(_recarregar);
    _carregar();
  }

  @override
  void dispose() {
    _catalogo?.removeListener(_recarregar);
    super.dispose();
  }

  void _carregar() {
    _future = _repository.search(categorySlug: _selected.slug, limit: 30);
  }

  /// Chamado quando o lojista cadastra, edita ou arquiva algo na aba Vender.
  void _recarregar() {
    if (mounted) {
      setState(_carregar);
    }
  }

  Future<void> _puxarParaAtualizar() async {
    setState(_carregar);
    await _future;
  }

  void _selecionar(Category category) {
    setState(() {
      _selected = category;
      _carregar();
    });
  }

  void _abrirProduto(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailPage(preview: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _puxarParaAtualizar,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 28),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Header(onOpenCart: widget.onOpenCart),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SearchField(),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: PromoBanner(),
            ),
            const SizedBox(height: 20),
            CategoryTabs(
              categories: _categories,
              selected: _selected,
              onSelected: _selecionar,
            ),
            const SizedBox(height: 22),
            AsyncView<ProductPage>(
              future: _future!,
              onRetry: () => setState(_carregar),
              minHeight: 320,
              builder: (BuildContext context, ProductPage page) =>
                  _Catalogo(page: page, onOpenProduct: _abrirProduto),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conteúdo da vitrine já resolvido: a faixa de ofertas e a grade.
class _Catalogo extends StatelessWidget {
  const _Catalogo({required this.page, required this.onOpenProduct});

  final ProductPage page;
  final ValueChanged<Product> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final List<Product> items = page.items;
    final List<Product> deals =
        items.where((Product product) => product.hasDiscount).toList();

    if (items.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'Nenhum produto nesta categoria.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Sem `compareAtPriceCents` no backend, a API nunca devolve desconto
        // e esta faixa some sozinha — nada de seção vazia na tela.
        if (deals.isNotEmpty) ...<Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SectionTitle('Ofertas do dia'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: deals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (BuildContext context, int index) {
                final Product product = deals[index];
                return SizedBox(
                  width: 165,
                  child: ProductCard(
                    product: product,
                    onTap: () => onOpenProduct(product),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 26),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionTitle(
            'Tudo na vitrine',
            trailing: Text(
              '${items.length} ite${items.length == 1 ? 'm' : 'ns'}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 22,
            childAspectRatio: 0.70,
          ),
          itemBuilder: (BuildContext context, int index) {
            final Product product = items[index];
            return ProductCard(
              product: product,
              onTap: () => onOpenProduct(product),
            );
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenCart});

  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) {
    final int cartCount = CartScope.of(context).totalQuantity;

    return Row(
      children: <Widget>[
        const Text(
          'Achou!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            IconButton(
              onPressed: onOpenCart,
              iconSize: 24,
              color: AppColors.textPrimary,
              icon: const Icon(Icons.shopping_bag_outlined),
            ),
            if (cartCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
