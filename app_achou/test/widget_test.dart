import 'package:app_achou/data/repositories/auth_repository.dart';
import 'package:app_achou/data/repositories/checkout_repository.dart';
import 'package:app_achou/data/repositories/mock_product_repository.dart';
import 'package:app_achou/data/repositories/mock_seller_repository.dart';
import 'package:app_achou/main.dart';
import 'package:app_achou/state/app_scope.dart';
import 'package:app_achou/state/catalog_signal.dart';
import 'package:app_achou/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Sem latência: o teste não precisa exercitar o spinner, e um
  // CircularProgressIndicator na tela faria `pumpAndSettle` nunca terminar.
  AchouApp montarApp() {
    return AchouApp(
      dependencies: AppDependencies(
        products: const MockProductRepository(latency: Duration.zero),
        seller: MockSellerRepository(latency: Duration.zero),
        checkout: MockCheckoutRepository(latency: Duration.zero),
        catalog: CatalogSignal(),
      ),
      session: SessionController(const MockAuthRepository()),
    );
  }

  testWidgets('a vitrine carrega e mostra a navegação inferior',
      (WidgetTester tester) async {
    await tester.pumpWidget(montarApp());
    await tester.pumpAndSettle();

    expect(find.text('Achou!'), findsOneWidget);
    expect(find.text('Ofertas do dia'), findsOneWidget);
    expect(find.text('Vender'), findsOneWidget);
  });

  testWidgets('a aba Sacola mostra o item inicial mockado',
      (WidgetTester tester) async {
    await tester.pumpWidget(montarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sacola'));
    await tester.pumpAndSettle();

    expect(find.text('Sua sacola'), findsOneWidget);
    expect(find.text('Finalizar compra'), findsOneWidget);
  });

  testWidgets('a aba Vender pede login antes do painel',
      (WidgetTester tester) async {
    await tester.pumpWidget(montarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vender'));
    await tester.pumpAndSettle();

    expect(find.text('ÁREA DO LOJISTA'), findsOneWidget);

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('PAINEL DO VENDEDOR'), findsOneWidget);
  });
}
