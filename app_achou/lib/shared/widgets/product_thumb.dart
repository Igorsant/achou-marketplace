import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../data/models/product.dart';

/// Imagem do produto. Sem integração, desenha um placeholder escuro com o
/// ícone da categoria; quando `imageUrl` existir, a rede assume.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.product,
    this.radius = 16,
    this.iconSize = 40,
  });

  final Product product;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _placeholder(),
          if (product.imageUrl.isNotEmpty)
            Image.network(
              product.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.thumbGradient),
      child: Center(
        child: Icon(
          _categoryIcon(product.category),
          size: iconSize,
          color: Colors.white.withValues(alpha: 0.28),
        ),
      ),
    );
  }

  static IconData _categoryIcon(String category) {
    switch (category) {
      case 'Áudio':
        return Icons.headphones_rounded;
      case 'Games':
        return Icons.sports_esports_rounded;
      case 'Celulares':
        return Icons.smartphone_rounded;
      case 'Computadores':
        return Icons.laptop_mac_rounded;
      case 'Wearables':
        return Icons.watch_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
  }
}
