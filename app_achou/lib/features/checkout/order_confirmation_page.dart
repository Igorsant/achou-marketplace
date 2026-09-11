import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../core/formatters.dart';
import '../../data/models/order.dart';
import '../../shared/widgets/gradient_button.dart';

class OrderConfirmationPage extends StatelessWidget {
  const OrderConfirmationPage({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 24),
              const Text(
                'Pedido confirmado',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'O pagamento foi autorizado e a loja já foi avisada.',
                style: AppTypography.body,
              ),
              const SizedBox(height: 32),
              _Linha(rotulo: 'PEDIDO', valor: order.numero),
              _Linha(rotulo: 'STATUS', valor: order.status),
              if (order.paymentRef != null)
                _Linha(rotulo: 'AUTORIZAÇÃO', valor: order.paymentRef!),
              _Linha(rotulo: 'TOTAL', valor: formatBrl(order.totalCents)),
              const Spacer(),
              const Text(
                'Pedido simulado: não existe cobrança nem entrega. Quando o '
                '/v1/orders existir, esta tela passa a mostrar o pedido real.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Voltar à vitrine',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(rotulo, style: AppTypography.label),
          Flexible(
            child: Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.price.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
