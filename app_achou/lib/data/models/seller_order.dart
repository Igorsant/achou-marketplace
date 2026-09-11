/// Pedido recebido pela loja, no formato agrupado de `/v1/seller/orders`.
class SellerOrder {
  const SellerOrder({
    required this.orderId,
    required this.status,
    required this.buyerName,
    required this.subtotalCents,
    required this.itemCount,
    this.simulated = false,
  });

  final String orderId;
  final String status;
  final String buyerName;
  final int subtotalCents;
  final int itemCount;

  /// Veio do checkout simulado do app, não da API. Marcado na tela para
  /// ninguém confundir demonstração com venda de verdade.
  final bool simulated;

  factory SellerOrder.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? buyer = json['buyer'] as Map<String, dynamic>?;
    final List<dynamic> items = json['items'] as List<dynamic>? ?? <dynamic>[];

    return SellerOrder(
      orderId: json['orderId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      buyerName: buyer?['name'] as String? ?? 'Comprador',
      subtotalCents: json['subtotalCents'] as int? ?? 0,
      itemCount: items.length,
    );
  }
}
