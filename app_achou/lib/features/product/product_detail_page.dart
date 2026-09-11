import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../core/formatters.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/discount_badge.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/product_card.dart';
import '../../shared/widgets/product_thumb.dart';
import '../../shared/widgets/quantity_stepper.dart';
import '../../shared/widgets/section_title.dart';
import '../../state/app_scope.dart';
import '../../state/cart_controller.dart';

/// Recebe o produto resumido que veio da listagem e busca o completo.
///
/// A listagem da API não traz descrição nem categoria; o cabeçalho usa o
/// resumo para aparecer na hora, e o corpo espera o detalhe.
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key, required this.preview});

  final Product preview;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late final ProductRepository _repository;
  Future<ProductDetails>? _future;
  int _quantity = 1;
  Product? _carregado;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) {
      return;
    }
    _repository = AppScope.of(context).products;
    _carregar();
  }

  void _carregar() {
    _future = _repository.details(widget.preview.id);
  }

  void _adicionarNaSacola() {
    final Product product = _carregado ?? widget.preview;
    CartScope.of(context).add(product, quantity: _quantity);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.title} foi para a sacola.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: <Widget>[
          ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              SizedBox(
                height: 340,
                child: ProductThumb(
                  product: widget.preview,
                  radius: 0,
                  iconSize: 88,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: AsyncView<ProductDetails>(
                    future: _future!,
                    onRetry: () => setState(_carregar),
                    minHeight: 260,
                    builder: (BuildContext context, ProductDetails detalhe) {
                      // Guardado para o botão da barra inferior usar o produto
                      // completo, não o resumo da listagem.
                      _carregado = detalhe.product;
                      return _Details(
                        product: detalhe.product,
                        related: detalhe.related,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _CircleButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    _CircleButton(
                      icon: Icons.shopping_bag_outlined,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BuyBar(
        quantity: _quantity,
        onIncrement: () => setState(() => _quantity++),
        onDecrement: () =>
            setState(() => _quantity = _quantity > 1 ? _quantity - 1 : 1),
        onAddToCart: _adicionarNaSacola,
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.product, required this.related});

  final Product product;
  final List<Product> related;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(_etiqueta(product), style: AppTypography.label),
        const SizedBox(height: 10),
        Text(
          product.title,
          style: const TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            if (product.hasDiscount) ...<Widget>[
              DiscountBadge(percent: product.discountPercent),
              const SizedBox(width: 10),
            ],
            Text(
              formatBrl(product.priceCents),
              style: AppTypography.priceLarge,
            ),
            if (product.hasDiscount) ...<Widget>[
              const SizedBox(width: 10),
              Text(
                formatBrl(product.compareAtPriceCents!),
                style: AppTypography.priceOld,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${product.inStock ? 'Em estoque' : 'Indisponível'} · garantia de '
          '${product.warrantyMonths} meses',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (product.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text(product.description, style: AppTypography.body),
        ],
        if (related.isNotEmpty) ...<Widget>[
          const SizedBox(height: 28),
          const SectionTitle('Você também pode gostar'),
          const SizedBox(height: 14),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (BuildContext context, int index) {
                final Product item = related[index];
                return SizedBox(
                  width: 165,
                  child: ProductCard(
                    product: item,
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductDetailPage(preview: item),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 28),
      ],
    );
  }

  /// "ÁUDIO · SOMLIVRE ÁUDIO" — omite o lado que vier vazio.
  static String _etiqueta(Product product) {
    final List<String> partes = <String>[
      if (product.category.isNotEmpty) product.category.toUpperCase(),
      if (product.seller.isNotEmpty) product.seller.toUpperCase(),
    ];
    return partes.join(' · ');
  }
}

class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    required this.onAddToCart,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: <Widget>[
              QuantityStepper(
                quantity: quantity,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Adicionar à sacola',
                  onPressed: onAddToCart,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
