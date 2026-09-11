import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/order.dart';

/// Fecha o pedido e autoriza o pagamento.
///
/// Hoje só existe a implementação simulada: `/v1/orders` e
/// `/v1/orders/:id/payment` estão no `docs/api-design.md` mas não foram
/// implementados. Quando existirem, entra um `HttpCheckoutRepository` aqui do
/// lado e as telas não mudam — mesmo caminho do catálogo.
///
/// É um `ChangeNotifier` porque o pedido criado precisa aparecer em duas
/// telas que não pediram por ele: o histórico na sacola e a aba de pedidos
/// do lojista.
abstract class CheckoutRepository extends ChangeNotifier {
  Future<Order> finalizar({
    required List<CartItem> items,
    required int shippingCents,
    required PaymentMethod method,
    required String idempotencyKey,
  });

  /// Do mais recente para o mais antigo.
  List<Order> get historico;
}

/// Gateway de faz de conta.
class MockCheckoutRepository extends CheckoutRepository {
  MockCheckoutRepository({
    this.latency = const Duration(milliseconds: 1200),
  });

  /// Demora de propósito: pagamento que responde instantaneamente esconde a
  /// necessidade de estado de carregamento, e é aí que a tela real quebra.
  final Duration latency;

  /// Pedidos já criados, por chave de idempotência. É o que faz repetir a
  /// mesma requisição devolver o mesmo pedido em vez de cobrar de novo.
  final Map<String, Order> _porChave = <String, Order>{};

  final Random _random = Random();

  @override
  List<Order> get historico =>
      _porChave.values.toList().reversed.toList(growable: false);

  @override
  Future<Order> finalizar({
    required List<CartItem> items,
    required int shippingCents,
    required PaymentMethod method,
    required String idempotencyKey,
  }) async {
    final Order? existente = _porChave[idempotencyKey];
    if (existente != null) {
      return existente;
    }

    await Future<void>.delayed(latency);

    final List<OrderLine> linhas = items
        .map((CartItem item) => OrderLine(
              title: item.product.title,
              quantity: item.quantity,
              unitPriceCents: item.product.priceCents,
              sellerName: item.product.seller,
            ))
        .toList();

    final int subtotal = linhas.fold(
      0,
      (int total, OrderLine line) => total + line.totalCents,
    );
    final bool autorizado = method != PaymentMethod.cartaoRecusado;

    final Order pedido = Order(
      id: 'ord_${_hex(8)}',
      status: autorizado ? Order.pago : Order.recusado,
      lines: linhas,
      totalCents: subtotal + shippingCents,
      createdAt: DateTime.now(),
      idempotencyKey: idempotencyKey,
      paymentRef: autorizado ? 'mock_${_hex(10)}' : null,
    );

    _porChave[idempotencyKey] = pedido;
    notifyListeners();
    return pedido;
  }

  String _hex(int caracteres) {
    const String alfabeto = '0123456789abcdef';
    return List<String>.generate(
      caracteres,
      (_) => alfabeto[_random.nextInt(alfabeto.length)],
    ).join();
  }
}
