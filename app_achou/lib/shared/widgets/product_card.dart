import 'package:flutter/material.dart';

import '../../core/app_typography.dart';
import '../../data/models/product.dart';
import 'discount_badge.dart';
import 'price_tag.dart';
import 'product_thumb.dart';

/// Card usado tanto na lista horizontal quanto na grade da vitrine.
///
/// A legenda tem altura fixa ([_alturaLegenda]) por dois motivos: os preços
/// ficam alinhados entre cards vizinhos, e a imagem — que é o widget flexível —
/// absorve toda a variação de altura do card. Assim o layout não depende de
/// quanto espaço a fonte resolve ocupar, que é o que estourava em telas
/// menores e no ambiente de teste.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap});

  static const double _alturaTitulo = 36;
  static const double _alturaPreco = 20;
  static const double _alturaLegenda = _alturaTitulo + 6 + _alturaPreco;

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: ProductThumb(product: product)),
                if (product.hasDiscount)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: DiscountBadge(percent: product.discountPercent),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _alturaLegenda,
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: _alturaTitulo,
                    child: Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.productName,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: _alturaPreco,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PriceTag(product: product),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
