import 'package:app_achou/data/mock/mock_products.dart';
import 'package:app_achou/data/models/product.dart';
import 'package:app_achou/state/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR 0002 — o carrinho como ele existe hoje: em memória, no cliente.
///
/// O ADR decide mover esse estado para o servidor (§2.1) e isso está diferido.
/// Enquanto estiver, o comportamento atual é o que está em produção, e vale
/// testá-lo pelas mesmas invariantes que a decisão exige do servidor depois:
/// uma linha por produto, quantidade somada, nenhum preço guardado.
///
/// Quando `/v1/cart` existir, este arquivo vira o teste do cache local e as
/// mesmas asserções passam a valer contra a API em
/// `backend/test/adr-0002-carrinho.e2e-spec.ts`.
void main() {
  final Product headphone = MockProducts.byId('p1');
  final Product fones = MockProducts.byId('p2');

  group('ADR 0002 §2.2 — uma linha por produto', () {
    test('adicionar o mesmo produto soma a quantidade em uma linha só', () {
      final CartController cart = CartController();

      cart.add(headphone);
      cart.add(headphone, quantity: 2);

      expect(cart.items.length, 1);
      expect(cart.items.single.quantity, 3);
      expect(cart.totalQuantity, 3);
    });

    test('produtos diferentes ocupam linhas diferentes', () {
      final CartController cart = CartController();

      cart.add(headphone);
      cart.add(fones);

      expect(cart.items.length, 2);
    });

    test('decrementar até zero remove a linha, não deixa quantidade 0', () {
      final CartController cart = CartController();
      cart.add(headphone);

      cart.decrement(headphone.id);

      expect(cart.items, isEmpty);
      expect(cart.isEmpty, isTrue);
    });
  });

  group('ADR 0002 §2.2 — o carrinho não guarda preço', () {
    /// O `CartItem` referencia o `Product` e multiplica na hora, em vez de
    /// copiar o valor. É a mesma decisão que `cart_items` materializa no banco
    /// ao não ter coluna de preço: um lugar só decide quanto custa.
    test('o total é derivado do produto, não de um valor copiado', () {
      final CartController cart = CartController();
      cart.add(headphone, quantity: 2);

      expect(cart.subtotalCents, headphone.priceCents * 2);
      expect(cart.items.single.totalCents, headphone.priceCents * 2);
    });

    test('sacola vazia não cobra frete', () {
      final CartController cart = CartController();

      expect(cart.shippingCents, 0);
      expect(cart.totalCents, 0);
    });

    /// Dívida registrada no ADR 0002 §4: o frete é constante de cliente. O
    /// teste fixa o comportamento atual para que a migração para o servidor
    /// seja uma mudança visível, não silenciosa.
    test('com itens, o frete é a constante do cliente (dívida do §4)', () {
      final CartController cart = CartController();
      cart.add(headphone);

      expect(cart.shippingCents, CartController.flatShippingCents);
      expect(cart.totalCents, cart.subtotalCents + CartController.flatShippingCents);
    });
  });

  group('notificação de mudança', () {
    test('cada operação avisa quem escuta', () {
      final CartController cart = CartController();
      int avisos = 0;
      cart.addListener(() => avisos++);

      cart.add(headphone);
      cart.increment(headphone.id);
      cart.decrement(headphone.id);
      cart.remove(headphone.id);
      cart.clear();

      expect(avisos, 5);
    });

    test('mexer em produto que não está na sacola não avisa à toa', () {
      final CartController cart = CartController();
      int avisos = 0;
      cart.addListener(() => avisos++);

      cart.increment('produto-inexistente');
      cart.decrement('produto-inexistente');

      expect(avisos, 0);
    });
  });
}
