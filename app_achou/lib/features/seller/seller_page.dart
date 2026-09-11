import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_typography.dart';
import '../../core/formatters.dart';
import '../../data/models/product.dart';
import '../../data/models/order.dart';
import '../../data/models/seller_order.dart';
import '../../data/remote/api_exception.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../data/repositories/seller_repository.dart';
import '../../shared/widgets/async_view.dart';
import '../../state/app_scope.dart';
import '../../state/catalog_signal.dart';
import '../../state/session_controller.dart';
import '../auth/login_page.dart';
import '../product/product_detail_page.dart';
import 'widgets/new_product_form.dart';
import 'widgets/seller_product_tile.dart';
import 'widgets/stat_card.dart';

class SellerPage extends StatefulWidget {
  const SellerPage({super.key, required this.onOpenStorefront});

  final VoidCallback onOpenStorefront;

  @override
  State<SellerPage> createState() => _SellerPageState();
}

class _SellerPageState extends State<SellerPage> {
  static const int _formTab = 0;
  static const int _ordersTab = 1;
  static const int _catalogTab = 2;

  SellerRepository? _repository;
  CatalogSignal? _catalogo;
  CheckoutRepository? _checkout;
  Future<SellerDashboard>? _future;
  int _currentTab = _catalogTab;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppDependencies deps = AppScope.of(context);
    _repository = deps.seller;
    _catalogo = deps.catalog;
    _checkout = deps.checkout;
  }

  void _carregar() {
    _future = _repository!.dashboard();
  }

  void _avisar(String mensagem) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
        ),
      );
  }

  void _sair(SessionController sessao) {
    sessao.signOut();
    setState(() {
      _future = null;
      _currentTab = _catalogTab;
    });
  }

  Future<void> _cadastrar(NewProductDraft draft) async {
    await _repository!.createProduct(draft);
    _catalogo?.mudou();
    if (!mounted) {
      return;
    }
    setState(() {
      _currentTab = _catalogTab;
      _carregar();
    });
    _avisar('${draft.title} publicado.');
  }

  /// Não recarrega o painel: o próprio controle já mostra o número novo, e um
  /// recarregamento piscaria a lista inteira a cada toque.
  Future<void> _ajustarEstoque(Product produto, int estoque) async {
    try {
      await _repository!.updateStock(produto.id, estoque);
      _catalogo?.mudou();
    } on ApiException catch (erro) {
      _avisar(erro.message);
      setState(_carregar);
    }
  }

  Future<void> _editar(Product produto) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return Padding(
          // Sobe com o teclado, senão os últimos campos ficam embaixo dele.
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('EDITAR PRODUTO', style: AppTypography.label),
                const SizedBox(height: 16),
                NewProductForm(
                  initial: produto,
                  submitLabel: 'Salvar alterações',
                  onSubmit: (NewProductDraft draft) async {
                    await _repository!.updateProduct(produto.id, draft);
                    _catalogo?.mudou();
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mounted) {
      setState(_carregar);
    }
  }

  Future<void> _restaurar(Product produto) async {
    try {
      await _repository!.restoreProduct(produto.id);
      _catalogo?.mudou();
      if (mounted) {
        setState(_carregar);
      }
      _avisar('${produto.title} voltou para a vitrine.');
    } on ApiException catch (erro) {
      _avisar(erro.message);
    }
  }

  Future<void> _arquivar(Product produto) async {
    final bool confirmado = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Arquivar produto?'),
            content: Text(
              '"${produto.title}" sai da vitrine. O histórico de pedidos '
              'continua intacto.',
              style: AppTypography.body,
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Arquivar',
                    style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmado) {
      return;
    }

    try {
      await _repository!.archiveProduct(produto.id);
      _catalogo?.mudou();
      if (mounted) {
        setState(_carregar);
      }
      _avisar('${produto.title} arquivado.');
    } on ApiException catch (erro) {
      _avisar(erro.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionController sessao = SessionScope.of(context);

    // A vitrine é pública; só o painel exige conta.
    if (!sessao.autenticado) {
      return LoginPage(onEntrou: () => setState(_carregar));
    }

    // Memoiza: sem isto, cada rebuild dispararia uma chamada nova à API.
    _future ??= _repository!.dashboard();

    return SafeArea(
      bottom: false,
      child: AsyncView<SellerDashboard>(
        future: _future!,
        onRetry: () => setState(_carregar),
        minHeight: 420,
        builder: (BuildContext context, SellerDashboard painel) {
          final String loja = painel.storeName.isNotEmpty
              ? painel.storeName
              : sessao.session!.userName;

          // Os pedidos do checkout simulado não existem na API, mas são o
          // único jeito de a loja receber um pedido hoje — entram na lista
          // marcados, junto com os que vierem de `/v1/seller/orders`.
          final List<SellerOrder> simulados = _checkout!.historico
              .where((Order pedido) => pedido.aprovado)
              .map((Order pedido) => pedido.paraLoja(loja))
              .whereType<SellerOrder>()
              .toList();

          final List<SellerOrder> pedidos = <SellerOrder>[
            ...simulados,
            ...painel.orders,
          ];
          final int receitaCents = painel.revenueCents +
              simulados.fold(
                0,
                (int total, SellerOrder pedido) => total + pedido.subtotalCents,
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(loja, style: AppTypography.pageTitle),
                  ),
                  TextButton(
                    onPressed: () => _sair(sessao),
                    child: const Text(
                      'Sair',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'PAINEL DO VENDEDOR',
                style: AppTypography.label.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatCard(
                      label: 'Produtos',
                      value: '${painel.activeProducts.length}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Pedidos',
                      value: '${pedidos.length}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Receita',
                      value: formatBrl(receitaCents),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _TabChips(
                labels: <String>[
                  'Cadastrar produto',
                  pedidos.isEmpty ? 'Pedidos' : 'Pedidos · ${pedidos.length}',
                  'Catálogo · ${painel.products.length}',
                ],
                currentIndex: _currentTab,
                onChanged: (int index) => setState(() => _currentTab = index),
              ),
              const SizedBox(height: 22),
              if (_currentTab == _formTab)
                NewProductForm(onSubmit: _cadastrar)
              else if (_currentTab == _ordersTab)
                _OrdersSection(orders: pedidos)
              else
                _CatalogSection(
                  catalog: painel.products,
                  publicados: painel.activeProducts.length,
                  onOpenStorefront: widget.onOpenStorefront,
                  onNew: () => setState(() => _currentTab = _formTab),
                  onStockChanged: _ajustarEstoque,
                  onEdit: _editar,
                  onArchive: _arquivar,
                  onRestore: _restaurar,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CatalogSection extends StatelessWidget {
  const _CatalogSection({
    required this.catalog,
    required this.publicados,
    required this.onOpenStorefront,
    required this.onNew,
    required this.onStockChanged,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
  });

  final List<Product> catalog;
  final int publicados;
  final VoidCallback onOpenStorefront;
  final VoidCallback onNew;
  final void Function(Product produto, int estoque) onStockChanged;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onArchive;
  final ValueChanged<Product> onRestore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '$publicados publicados',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onOpenStorefront,
              child: const Text(
                'Vitrine →',
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onNew,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                backgroundColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '+ Novo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (catalog.isEmpty)
          const _Vazio(
            icon: Icons.inventory_2_outlined,
            titulo: 'Nenhum produto publicado',
            detalhe: 'Cadastre o primeiro pela aba ao lado.',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < catalog.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  SellerProductTile(
                    product: catalog[i],
                    onStockChanged: (int estoque) =>
                        onStockChanged(catalog[i], estoque),
                    onEdit: () => onEdit(catalog[i]),
                    onArchive: () => onArchive(catalog[i]),
                    onRestore: () => onRestore(catalog[i]),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductDetailPage(preview: catalog[i]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({required this.orders});

  final List<SellerOrder> orders;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const _Vazio(
        icon: Icons.receipt_long_outlined,
        titulo: 'Nenhum pedido ainda',
        detalhe: 'Os pedidos aparecem aqui assim que a loja vender.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < orders.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1),
            _OrderTile(order: orders[i]),
          ],
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final SellerOrder order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  order.buyerName,
                  style: AppTypography.productName.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.status} · ${order.itemCount} '
                  'ITE${order.itemCount == 1 ? 'M' : 'NS'}'
                  '${order.simulated ? ' · SIMULADO' : ''}',
                  style: AppTypography.label,
                ),
              ],
            ),
          ),
          Text(formatBrl(order.subtotalCents), style: AppTypography.price),
        ],
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({
    required this.icon,
    required this.titulo,
    required this.detalhe,
  });

  final IconData icon;
  final String titulo;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 36, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(titulo, style: AppTypography.sectionTitle),
          const SizedBox(height: 6),
          Text(
            detalhe,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChips extends StatelessWidget {
  const _TabChips({
    required this.labels,
    required this.currentIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) {
          final bool isSelected = index == currentIndex;
          return GestureDetector(
            onTap: () => onChanged(index),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
