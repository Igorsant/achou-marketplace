import 'package:flutter/material.dart';

/// Paleta única do app Achou!.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFFFBF6F3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF4EDE8);
  static const Color border = Color(0xFFEBE0D9);
  static const Color textPrimary = Color(0xFF17110E);
  static const Color textSecondary = Color(0xFF8B807A);
  static const Color primary = Color(0xFFE8102E);
  static const Color primaryDark = Color(0xFFC00020);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[Color(0xFFFF3B4E), Color(0xFFD90429)],
  );

  static const LinearGradient thumbGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF2E2724), Color(0xFF0D0A09)],
  );
}
