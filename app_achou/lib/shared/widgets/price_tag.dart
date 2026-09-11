import 'package:flutter/material.dart';

import '../../core/app_typography.dart';
import '../../core/formatters.dart';
import '../../data/models/product.dart';

/// Preço atual e, quando houver desconto, o preço antigo riscado ao lado.
class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.product,
    this.style,
    this.showOldPrice = true,
  });

  final Product product;
  final TextStyle? style;
  final bool showOldPrice;

  @override
  Widget build(BuildContext context) {
    final Widget price = Text(
      formatBrl(product.priceCents),
      maxLines: 1,
      style: style ?? AppTypography.price,
    );

    if (!showOldPrice || !product.hasDiscount) {
      return price;
    }

    // Alinhamento pelo fim, não pela baseline: baseline entre dois tamanhos
    // de fonte diferentes faz a linha crescer mais que o previsto.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        price,
        const SizedBox(width: 8),
        Text(
          formatBrl(product.compareAtPriceCents!),
          maxLines: 1,
          style: AppTypography.priceOld,
        ),
      ],
    );
  }
}
