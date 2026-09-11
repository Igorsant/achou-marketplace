import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/product_card.dart';
import '../../shared/widgets/search_field.dart';
import '../../state/app_scope.dart';
import '../../state/catalog_signal.dart';
import '../product/product_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  /// Espera o usuário parar de digitar antes de consultar a API — sem isso,
  /// "notebook" dispara oito buscas.
  static const Duration _debounce = Duration(milliseconds: 350);

  final TextEditingController _controller = TextEditingController();
  late final ProductRepository _repository;
  CatalogSignal? _catalogo;
  Timer? _timer;
  String _term = '';
  Future<ProductPage>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) {
      return;
    }
    final AppDependencies deps = AppScope.of(context);
    _repository = deps.products;
    _catalogo = deps.catalog..addListener(_recarregar);
    _carregar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _catalogo?.removeListener(_recarregar);
    _controller.dispose();
    super.dispose();
  }

  /// Chamado quando o lojista mexe no catálogo na aba Vender.
  void _recarregar() {
    if (mounted) {
      setState(_carregar);
    }
  }

  void _carregar() {
    _future = _repository.search(term: _term, limit: 30);
  }

  void _aoDigitar(String valor) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _term = valor;
        _carregar();
      });
    });
  }

  void _abrirProduto(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailPage(preview: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text('Buscar', style: AppTypography.pageTitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: SearchField(
              controller: _controller,
              onChanged: _aoDigitar,
            ),
          ),
          Expanded(
            child: AsyncView<ProductPage>(
              future: _future!,
              onRetry: () => setState(_carregar),
              minHeight: 300,
              builder: (BuildContext context, ProductPage page) =>
                  _Resultados(page: page, onOpenProduct: _abrirProduto),
            ),
          ),
        ],
      ),
    );
  }
}

class _Resultados extends StatelessWidget {
  const _Resultados({required this.page, required this.onOpenProduct});

  final ProductPage page;
  final ValueChanged<Product> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final List<Product> items = page.items;

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Nada encontrado para essa busca.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${items.length} RESULTADO${items.length == 1 ? '' : 'S'}',
            style: AppTypography.label,
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 22,
              childAspectRatio: 0.70,
            ),
            itemBuilder: (BuildContext context, int index) {
              final Product product = items[index];
              return ProductCard(
                product: product,
                onTap: () => onOpenProduct(product),
              );
            },
          ),
        ),
      ],
    );
  }
}
