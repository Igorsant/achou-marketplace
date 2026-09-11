import 'package:flutter/widgets.dart';

import '../data/repositories/checkout_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/seller_repository.dart';
import 'catalog_signal.dart';

/// Dependências que as telas consomem.
class AppDependencies {
  const AppDependencies({
    required this.products,
    required this.seller,
    required this.checkout,
    required this.catalog,
  });

  final ProductRepository products;
  final SellerRepository seller;
  final CheckoutRepository checkout;
  final CatalogSignal catalog;
}

/// Ponto único de injeção. Trocar mock por API é trocar o que o `main.dart`
/// coloca aqui — nenhuma tela sabe qual implementação está rodando.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final AppScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado acima deste widget.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
