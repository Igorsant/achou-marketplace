import 'seller_order.dart';

/// Forma de pagamento oferecida no checkout.
///
/// Todas são simuladas. Não existe cobrança, e o app de propósito não coleta
/// número de cartão: o gateway real é assunto de outra fase.
enum PaymentMethod {
  pix('Pix', 'Simulado — aprova na hora'),
  cartaoAprovado('Cartão de teste', 'Simulado — autoriza o pagamento'),
  cartaoRecusado('Cartão de teste recusado', 'Simulado — cai em recusa');

  const PaymentMethod(this.label, this.detail);

  final String label;
  final String detail;
}

/// Item congelado no momento da compra.
///
/// Guarda título e preço unitário copiados, e não o `Product`: reajuste do
/// lojista depois da compra não pode reescrever pedido passado — é a mesma
/// razão pela qual o backend tem `title_snapshot` e `unit_price_cents`.
class OrderLine {
  const OrderLine({
    required this.title,
    required this.quantity,
    required this.unitPriceCents,
    required this.sellerName,
  });

  final String title;
  final int quantity;
  final int unitPriceCents;
  final String sellerName;

  int get totalCents => unitPriceCents * quantity;
}

/// Pedido, com os mesmos estados da máquina descrita no README da API.
class Order {
  const Order({
    required this.id,
    required this.status,
    required this.lines,
    required this.totalCents,
    required this.createdAt,
    required this.idempotencyKey,
    this.paymentRef,
  });

  static const String pendente = 'PENDING_PAYMENT';
  static const String pago = 'PAID';
  static const String recusado = 'PAYMENT_FAILED';

  final String id;
  final String status;
  final List<OrderLine> lines;
  final int totalCents;
  final DateTime createdAt;
  final String idempotencyKey;

  /// Identificador devolvido pelo gateway. No mock é inventado.
  final String? paymentRef;

  bool get aprovado => status == pago;
  bool get falhou => status == recusado;

  int get itemCount =>
      lines.fold(0, (int total, OrderLine line) => total + line.quantity);

  /// Curto, para mostrar na tela — o id inteiro não cabe e não ajuda.
  String get numero => id.length <= 8 ? id : id.substring(id.length - 8);

  /// Recorta o pedido no que interessa a uma loja: o painel do lojista mostra
  /// o pedido inteiro, mas só os itens dela. `null` quando a loja não vendeu
  /// nada neste pedido.
  SellerOrder? paraLoja(String storeName) {
    final List<OrderLine> daLoja = lines
        .where((OrderLine line) => line.sellerName == storeName)
        .toList();

    if (daLoja.isEmpty) {
      return null;
    }

    return SellerOrder(
      orderId: numero,
      status: status,
      buyerName: 'Comprador do app',
      subtotalCents: daLoja.fold(
        0,
        (int total, OrderLine line) => total + line.totalCents,
      ),
      itemCount: daLoja.length,
      simulated: true,
    );
  }
}
