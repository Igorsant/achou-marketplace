import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/order.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../state/app_scope.dart';
import '../../state/cart_controller.dart';
import 'order_confirmation_page.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  /// Nulável, não `late final`: esta tela depende do `CartScope`, então
  /// `didChangeDependencies` roda de novo a cada mudança na sacola — e um
  /// `late final` estoura na segunda atribuição.
  CheckoutRepository? _repository;
  PaymentMethod _metodo = PaymentMethod.pix;

  /// Gerada uma vez por tentativa de pagamento: repetir o toque no botão com
  /// a mesma chave devolve o mesmo pedido, em vez de criar outro.
  String _chave = gerarIdempotencyKey();

  bool _processando = false;
  String? _erro;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = AppScope.of(context).checkout;
  }

  Future<void> _pagar() async {
    final CartController carrinho = CartScope.of(context);
    final List<CartItem> itens = carrinho.items;
    if (itens.isEmpty) {
      return;
    }

    setState(() {
      _processando = true;
      _erro = null;
    });

    final Order pedido = await _repository!.finalizar(
      items: itens,
      shippingCents: carrinho.shippingCents,
      method: _metodo,
      idempotencyKey: _chave,
    );

    if (!mounted) {
      return;
    }

    if (pedido.aprovado) {
      carrinho.clear();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderConfirmationPage(order: pedido),
        ),
      );
      return;
    }

    setState(() {
      _processando = false;
      _erro = 'O pagamento foi recusado. Escolha outra forma e tente de novo.';
      // Tentativa nova, pedido novo: a chave antiga já está gasta com a recusa.
      _chave = gerarIdempotencyKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final CartController carrinho = CartScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pagamento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: <Widget>[
          const _AvisoSimulacao(),
          const SizedBox(height: 24),
          Text('RESUMO', style: AppTypography.label),
          const SizedBox(height: 12),
          _Resumo(carrinho: carrinho),
          const SizedBox(height: 28),
          Text('FORMA DE PAGAMENTO', style: AppTypography.label),
          const SizedBox(height: 12),
          for (final PaymentMethod metodo in PaymentMethod.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OpcaoPagamento(
                metodo: metodo,
                selecionado: metodo == _metodo,
                onTap: _processando
                    ? null
                    : () => setState(() => _metodo = metodo),
              ),
            ),
          if (_erro != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _erro!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: GradientButton(
              label: _processando
                  ? 'Processando…'
                  : 'Pagar ${formatBrl(carrinho.totalCents)}',
              onPressed: _processando || carrinho.isEmpty ? null : _pagar,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvisoSimulacao extends StatelessWidget {
  const _AvisoSimulacao();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Pagamento simulado. Nenhuma cobrança é feita e nenhum dado de '
              'cartão é pedido — o gateway real ainda não existe na API.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.carrinho});

  final CartController carrinho;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          for (final CartItem item in carrinho.items) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${item.quantity}× ${item.product.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(formatBrl(item.totalCents),
                    style: AppTypography.price.copyWith(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const Divider(height: 18),
          _Linha(
            rotulo: 'Frete',
            valor: formatBrl(carrinho.shippingCents),
          ),
          const SizedBox(height: 10),
          _Linha(
            rotulo: 'Total',
            valor: formatBrl(carrinho.totalCents),
            destaque: true,
          ),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.rotulo,
    required this.valor,
    this.destaque = false,
  });

  final String rotulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          rotulo,
          style: TextStyle(
            fontSize: destaque ? 16 : 14,
            fontWeight: destaque ? FontWeight.w700 : FontWeight.w500,
            color:
                destaque ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          valor,
          style: AppTypography.price.copyWith(fontSize: destaque ? 17 : 14),
        ),
      ],
    );
  }
}

class _OpcaoPagamento extends StatelessWidget {
  const _OpcaoPagamento({
    required this.metodo,
    required this.selecionado,
    required this.onTap,
  });

  final PaymentMethod metodo;
  final bool selecionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: selecionado ? AppColors.primary : AppColors.border,
            width: selecionado ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selecionado
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color:
                  selecionado ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    metodo.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metodo.detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
