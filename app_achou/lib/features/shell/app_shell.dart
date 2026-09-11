import 'package:flutter/material.dart';

import '../cart/cart_page.dart';
import '../home/home_page.dart';
import '../search/search_page.dart';
import '../seller/seller_page.dart';
import 'widgets/app_bottom_nav.dart';

/// Casca do app: mantém as quatro abas vivas e troca o conteúdo.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static const int homeTab = 0;
  static const int searchTab = 1;
  static const int cartTab = 2;
  static const int sellerTab = 3;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = AppShell.homeTab;

  void _goTo(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: <Widget>[
          HomePage(onOpenCart: () => _goTo(AppShell.cartTab)),
          const SearchPage(),
          CartPage(onKeepShopping: () => _goTo(AppShell.homeTab)),
          SellerPage(onOpenStorefront: () => _goTo(AppShell.homeTab)),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onChanged: _goTo,
      ),
    );
  }
}
