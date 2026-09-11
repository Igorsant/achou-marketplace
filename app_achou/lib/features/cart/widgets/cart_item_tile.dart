import 'package:flutter/material.dart';

import '../../../core/app_typography.dart';
import '../../../core/formatters.dart';
import '../../../data/models/cart_item.dart';
import '../../../shared/widgets/product_thumb.dart';
import '../../../shared/widgets/quantity_stepper.dart';

class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 86,
          height: 70,
          child: ProductThumb(product: item.product, radius: 12, iconSize: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.product.seller.toUpperCase(),
                  style: AppTypography.label),
              const SizedBox(height: 4),
              Text(
                item.product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.productName,
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  QuantityStepper(
                    quantity: item.quantity,
                    onIncrement: onIncrement,
                    onDecrement: onDecrement,
                  ),
                  const Spacer(),
                  Text(formatBrl(item.totalCents), style: AppTypography.price),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
