import 'package:flutter/widgets.dart';

import '../data/models/cart_item.dart';
import '../data/models/product.dart';

/// Estado da sacola. Mantido em memória enquanto `/v1/cart` não existe.
class CartController extends ChangeNotifier {
  CartController();

  /// Frete fixo da fase mockada — o backend ainda não calcula frete.
  static const int flatShippingCents = 2490;

  final List<CartItem> _items = <CartItem>[];

  List<CartItem> get items => List<CartItem>.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  int get totalQuantity =>
      _items.fold(0, (int sum, CartItem item) => sum + item.quantity);

  int get subtotalCents =>
      _items.fold(0, (int sum, CartItem item) => sum + item.totalCents);

  int get shippingCents => _items.isEmpty ? 0 : flatShippingCents;

  int get totalCents => subtotalCents + shippingCents;

  void add(Product product, {int quantity = 1}) {
    final int index = _indexOf(product.id);
    if (index == -1) {
      _items.add(CartItem(product: product, quantity: quantity));
    } else {
      _items[index] =
          _items[index].copyWith(quantity: _items[index].quantity + quantity);
    }
    notifyListeners();
  }

  void increment(String productId) {
    final int index = _indexOf(productId);
    if (index == -1) {
      return;
    }
    _items[index] = _items[index].copyWith(quantity: _items[index].quantity + 1);
    notifyListeners();
  }

  void decrement(String productId) {
    final int index = _indexOf(productId);
    if (index == -1) {
      return;
    }
    final int quantity = _items[index].quantity - 1;
    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      _items[index] = _items[index].copyWith(quantity: quantity);
    }
    notifyListeners();
  }

  void remove(String productId) {
    _items.removeWhere((CartItem item) => item.product.id == productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  int _indexOf(String productId) =>
      _items.indexWhere((CartItem item) => item.product.id == productId);
}

/// Disponibiliza o [CartController] para a árvore e reconstrói quem depende.
class CartScope extends InheritedNotifier<CartController> {
  const CartScope({
    super.key,
    required CartController controller,
    required super.child,
  }) : super(notifier: controller);

  static CartController of(BuildContext context) {
    final CartScope? scope =
        context.dependOnInheritedWidgetOfExactType<CartScope>();
    assert(scope != null, 'CartScope não encontrado acima deste widget.');
    return scope!.notifier!;
  }
}
