import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_typography.dart';
import '../../../core/formatters.dart';
import '../../../shared/widgets/gradient_button.dart';

class CartSummary extends StatelessWidget {
  const CartSummary({
    super.key,
    required this.subtotalCents,
    required this.shippingCents,
    required this.totalCents,
    required this.onCheckout,
  });

  final int subtotalCents;
  final int shippingCents;
  final int totalCents;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            children: <Widget>[
              _SummaryRow(label: 'Subtotal', value: formatBrl(subtotalCents)),
              const SizedBox(height: 8),
              _SummaryRow(label: 'Frete', value: formatBrl(shippingCents)),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Total',
                value: formatBrl(totalCents),
                emphasized: true,
              ),
              const SizedBox(height: 16),
              GradientButton(label: 'Finalizar compra', onPressed: onCheckout),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: emphasized ? 16 : 14,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            color:
                emphasized ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: emphasized
              ? AppTypography.price.copyWith(fontSize: 17)
              : AppTypography.price.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
        ),
      ],
    );
  }
}
