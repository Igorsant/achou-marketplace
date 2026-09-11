import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'data/mock/mock_products.dart';
import 'data/remote/api_client.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/checkout_repository.dart';
import 'data/repositories/http_product_repository.dart';
import 'data/repositories/http_seller_repository.dart';
import 'data/repositories/mock_product_repository.dart';
import 'data/repositories/mock_seller_repository.dart';
import 'features/shell/app_shell.dart';
import 'state/app_scope.dart';
import 'state/cart_controller.dart';
import 'state/catalog_signal.dart';
import 'state/session_controller.dart';

/// Liga a API sem tocar em código:
/// `flutter run --dart-define=USE_API=true`
const bool usarApi = bool.fromEnvironment('USE_API');

void main() {
  final ApiClient? api = usarApi ? ApiClient() : null;

  final AuthRepository auth =
      api == null ? const MockAuthRepository() : HttpAuthRepository(api);
  final SessionController session = SessionController(auth);

  final CatalogSignal catalogo = CatalogSignal();

  // Checkout é simulado nos dois modos: `/v1/orders` e o pagamento não
  // existem na API. Trocar por HTTP é trocar esta linha.
  final CheckoutRepository checkout = MockCheckoutRepository();

  final AppDependencies dependencies = api == null
      ? AppDependencies(
          products: const MockProductRepository(),
          seller: MockSellerRepository(),
          checkout: checkout,
          catalog: catalogo,
        )
      : AppDependencies(
          products: HttpProductRepository(api),
          seller: HttpSellerRepository(
            api: api,
            token: () => session.token,
            refresh: session.renovar,
          ),
          checkout: checkout,
          catalog: catalogo,
        );

  runApp(AchouApp(dependencies: dependencies, session: session));
}

class AchouApp extends StatefulWidget {
  const AchouApp({
    super.key,
    required this.dependencies,
    required this.session,
  });

  final AppDependencies dependencies;
  final SessionController session;

  @override
  State<AchouApp> createState() => _AchouAppState();
}

class _AchouAppState extends State<AchouApp> {
  final CartController _cart = CartController();

  @override
  void initState() {
    super.initState();
    // Item inicial só para a sacola nascer com conteúdo. Sai quando o
    // `/v1/cart` existir e o carrinho passar a vir do servidor.
    if (!usarApi) {
      _cart.add(MockProducts.byId('p1'));
    }
  }

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: widget.dependencies,
      child: SessionScope(
        controller: widget.session,
        child: CartScope(
          controller: _cart,
          child: MaterialApp(
            title: 'Achou!',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const AppShell(),
          ),
        ),
      ),
    );
  }
}
