import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';

/// Sistema tipográfico de corte editorial para NexusBO.
/// Prioriza contraste en titulares, interlineado equilibrado y lectura limpia.
abstract final class AppTypography {
  static TextTheme buildTextTheme(NexusColors colors) {
    return TextTheme(
      // Marca / Cabecera editorial principal
      displaySmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
        height: 1.12,
        color: colors.textPrimary,
      ),
      // Titular de noticia principal destacada (Hero)
      headlineMedium: TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.2,
        color: colors.textPrimary,
      ),
      // Titular en vista de lectura completa
      headlineSmall: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.24,
        color: colors.textPrimary,
      ),
      // Titular de noticia secundaria en el feed
      titleLarge: TextStyle(
        fontSize: 17.5,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        height: 1.26,
        color: colors.textPrimary,
      ),
      // Subtítulo de sección / bloques de ajustes
      titleMedium: TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
        color: colors.textPrimary,
      ),
      // Subtítulos compactos
      titleSmall: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.3,
        color: colors.textPrimary,
      ),
      // Cuerpo de lectura de artículo
      bodyLarge: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        height: 1.6,
        color: colors.textPrimary,
      ),
      // Extracto / sumario en el feed
      bodyMedium: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.05,
        height: 1.45,
        color: colors.textSecondary,
      ),
      // Metadatos secundarios (fuente, tiempo de publicación, pie de foto)
      bodySmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        height: 1.35,
        color: colors.textSecondary,
      ),
      // Etiquetas de categoría (ej. POLÍTICA, ECONOMÍA)
      labelMedium: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.75,
        height: 1.2,
        color: colors.primary,
      ),
      // Indicadores compactos y fechas de cabecera
      labelSmall: TextStyle(
        fontSize: 11.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        height: 1.2,
        color: colors.textSecondary,
      ),
    );
  }
}

