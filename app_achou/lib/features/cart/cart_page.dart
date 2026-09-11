import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../core/formatters.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/order.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../state/app_scope.dart';
import '../../state/cart_controller.dart';
import '../checkout/checkout_page.dart';
import 'widgets/cart_item_tile.dart';
import 'widgets/cart_summary.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key, required this.onKeepShopping});

  final VoidCallback onKeepShopping;

  void _checkout(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CheckoutPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CartController cart = CartScope.of(context);
    final CheckoutRepository checkout = AppScope.of(context).checkout;
    final List<CartItem> items = cart.items;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Text('Sua sacola', style: AppTypography.pageTitle),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: checkout,
              builder: (BuildContext context, _) {
                final List<Order> pedidos = checkout.historico;

                if (items.isEmpty && pedidos.isEmpty) {
                  return _EmptyCart(onKeepShopping: onKeepShopping);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: <Widget>[
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Text(
                          'Sua sacola está vazia.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    for (final CartItem item in items) ...<Widget>[
                      CartItemTile(
                        item: item,
                        onIncrement: () => cart.increment(item.product.id),
                        onDecrement: () => cart.decrement(item.product.id),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (items.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: cart.clear,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'ESVAZIAR SACOLA',
                            style: AppTypography.label,
                          ),
                        ),
                      ),
                    if (pedidos.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 26),
                      Text('SEUS PEDIDOS', style: AppTypography.label),
                      const SizedBox(height: 12),
                      for (final Order pedido in pedidos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PedidoTile(pedido: pedido),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
          CartSummary(
            subtotalCents: cart.subtotalCents,
            shippingCents: cart.shippingCents,
            totalCents: cart.totalCents,
            onCheckout: items.isEmpty ? null : () => _checkout(context),
          ),
        ],
      ),
    );
  }
}

/// Pedido já fechado. Enquanto `/v1/orders` não existir, estes pedidos vivem
/// na memória do app e somem quando ele fecha.
class _PedidoTile extends StatelessWidget {
  const _PedidoTile({required this.pedido});

  final Order pedido;

  @override
  Widget build(BuildContext context) {
    final bool aprovado = pedido.aprovado;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                aprovado
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                size: 16,
                color:
                    aprovado ? AppColors.textSecondary : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PEDIDO ${pedido.numero.toUpperCase()}',
                  style: AppTypography.label,
                ),
              ),
              Text(
                formatBrl(pedido.totalCents),
                style: AppTypography.price.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            pedido.lines
                .map((OrderLine line) => '${line.quantity}× ${line.title}')
                .join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            aprovado ? 'PAGO · SIMULADO' : 'PAGAMENTO RECUSADO · SIMULADO',
            style: AppTypography.label.copyWith(
              color: aprovado ? AppColors.textSecondary : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onKeepShopping});

  final VoidCallback onKeepShopping;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.shopping_bag_outlined,
              size: 44, color: AppColors.textSecondary),
          const SizedBox(height: 14),
          const Text('Sua sacola está vazia',
              style: AppTypography.sectionTitle),
          const SizedBox(height: 6),
          const Text(
            'Adicione produtos da vitrine para continuar.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onKeepShopping,
            child: const Text('Ver ofertas',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
