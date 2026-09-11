import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Estilos de texto reutilizados pelas telas.
class AppTypography {
  AppTypography._();

  static const List<String> _monoFallback = <String>[
    'Menlo',
    'Courier New',
    'monospace',
  ];

  /// Rótulo pequeno em caixa alta (categorias, vendedor, métricas).
  static const TextStyle label = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: _monoFallback,
    fontSize: 10,
    height: 1.3,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static const TextStyle price = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: _monoFallback,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle priceLarge = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: _monoFallback,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  static const TextStyle priceOld = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: _monoFallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    decoration: TextDecoration.lineThrough,
  );

  static const TextStyle metric = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: _monoFallback,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle productName = TextStyle(
    fontSize: 14,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.5,
    color: AppColors.textSecondary,
  );
}
