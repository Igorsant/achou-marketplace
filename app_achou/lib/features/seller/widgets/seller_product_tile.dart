import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_typography.dart';
import '../../../data/models/product.dart';
import '../../../shared/widgets/price_tag.dart';
import '../../../shared/widgets/product_thumb.dart';
import '../../../shared/widgets/quantity_stepper.dart';

class SellerProductTile extends StatelessWidget {
  const SellerProductTile({
    super.key,
    required this.product,
    this.onTap,
    this.onStockChanged,
    this.onEdit,
    this.onArchive,
    this.onRestore,
  });

  final Product product;
  final VoidCallback? onTap;
  final ValueChanged<int>? onStockChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final bool arquivado = product.isArchived;
    final bool temEstoque =
        product.stock != null && onStockChanged != null && !arquivado;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          children: <Widget>[
            // Arquivado fica apagado: continua na lista porque a API não
            // apaga de verdade, mas não é mais o que a loja está vendendo.
            Opacity(
              opacity: arquivado ? 0.45 : 1,
              child: SizedBox(
                width: 46,
                height: 46,
                child: ProductThumb(product: product, radius: 10, iconSize: 20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.productName.copyWith(
                      fontSize: 15,
                      color: arquivado
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (arquivado)
                    const _Etiqueta(texto: 'ARQUIVADO')
                  else if (temEstoque)
                    _ControleEstoque(
                      estoque: product.stock!,
                      onChanged: onStockChanged!,
                    )
                  else
                    Text(product.category.toUpperCase(),
                        style: AppTypography.label),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: arquivado ? 0.45 : 1,
              child: PriceTag(product: product, showOldPrice: false),
            ),
            if (onEdit != null || onArchive != null || onRestore != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 18, color: AppColors.textSecondary),
                onSelected: (String acao) {
                  switch (acao) {
                    case 'editar':
                      onEdit?.call();
                    case 'reativar':
                      onRestore?.call();
                    case 'arquivar':
                      onArchive?.call();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (onEdit != null)
                    const PopupMenuItem<String>(
                      value: 'editar',
                      child: Text('Editar'),
                    ),
                  if (arquivado && onRestore != null)
                    const PopupMenuItem<String>(
                      value: 'reativar',
                      child: Text('Reativar'),
                    )
                  else if (!arquivado && onArchive != null)
                    const PopupMenuItem<String>(
                      value: 'arquivar',
                      child: Text('Arquivar'),
                    ),
                ],
              )
            else
              const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(texto, style: AppTypography.label),
    );
  }
}

/// Estoque com ajuste inline.
///
/// O número muda na hora e a chamada à API espera o dedo parar: quem corrige
/// de 3 para 12 toca nove vezes, e nove `PATCH` seriam desperdício.
class _ControleEstoque extends StatefulWidget {
  const _ControleEstoque({required this.estoque, required this.onChanged});

  final int estoque;
  final ValueChanged<int> onChanged;

  @override
  State<_ControleEstoque> createState() => _ControleEstoqueState();
}

class _ControleEstoqueState extends State<_ControleEstoque> {
  static const Duration _espera = Duration(milliseconds: 700);

  late int _valor = widget.estoque;
  Timer? _timer;

  @override
  void didUpdateWidget(_ControleEstoque oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Só aceita o valor de fora quando não há alteração local pendente,
    // senão um recarregamento do painel desfaria o que foi tocado agora.
    if (_timer == null && widget.estoque != oldWidget.estoque) {
      _valor = widget.estoque;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ajustar(int passo) {
    final int novo = _valor + passo;
    if (novo < 0) {
      return;
    }

    setState(() => _valor = novo);
    _timer?.cancel();
    _timer = Timer(_espera, () {
      _timer = null;
      widget.onChanged(_valor);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        QuantityStepper(
          quantity: _valor,
          onIncrement: () => _ajustar(1),
          onDecrement: () => _ajustar(-1),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _valor == 0 ? 'SEM ESTOQUE' : 'EM ESTOQUE',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: _valor == 0 ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
