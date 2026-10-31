import 'package:flutter/material.dart';

/// Paleta oficial de NexusBO para modo claro y modo oscuro.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // MODO CLARO
  // ---------------------------------------------------------------------------
  static const Color lightPrimary = Color(0xFF006989);
  static const Color lightPrimaryDark = Color(0xFF00576F);
  static const Color lightPrimaryLight = Color(0xFFD6EEF2);

  static const Color lightBackground = Color(0xFFF7F8F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFEAEBED);

  static const Color lightTextPrimary = Color(0xFF172126);
  static const Color lightTextSecondary = Color(0xFF59666C);

  static const Color lightBorder = Color(0xFFD6DADD);
  static const Color lightAccent = Color(0xFF00A6A6);
  static const Color lightError = Color(0xFFC83C3C);

  // ---------------------------------------------------------------------------
  // MODO OSCURO
  // ---------------------------------------------------------------------------
  static const Color darkPrimary = Color(0xFF42B3C5);
  static const Color darkPrimaryContainer = Color(0xFF004B61);

  static const Color darkBackground = Color(0xFF101719);
  static const Color darkSurface = Color(0xFF172125);
  static const Color darkSurfaceSecondary = Color(0xFF202C30);

  static const Color darkTextPrimary = Color(0xFFEAEBED);
  static const Color darkTextSecondary = Color(0xFFAAB6BA);

  static const Color darkBorder = Color(0xFF344247);
  static const Color darkAccent = Color(0xFF5AD1C8);
  static const Color darkError = Color(0xFFFF716C);
}

/// Extensión de tema semántica para acceder a los tokens de color de NexusBO
/// desde cualquier widget mediante `context.nexusColors`.
@immutable
class NexusColors extends ThemeExtension<NexusColors> {
  const NexusColors({
    required this.primary,
    required this.primaryContainer,
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accent,
    required this.error,
  });

  final Color primary;
  final Color primaryContainer;
  final Color background;
  final Color surface;
  final Color surfaceSecondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color accent;
  final Color error;

  static const NexusColors light = NexusColors(
    primary: AppColors.lightPrimary,
    primaryContainer: AppColors.lightPrimaryLight,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceSecondary: AppColors.lightSurfaceSecondary,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    border: AppColors.lightBorder,
    accent: AppColors.lightAccent,
    error: AppColors.lightError,
  );

  static const NexusColors dark = NexusColors(
    primary: AppColors.darkPrimary,
    primaryContainer: AppColors.darkPrimaryContainer,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceSecondary: AppColors.darkSurfaceSecondary,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    border: AppColors.darkBorder,
    accent: AppColors.darkAccent,
    error: AppColors.darkError,
  );

  @override
  NexusColors copyWith({
    Color? primary,
    Color? primaryContainer,
    Color? background,
    Color? surface,
    Color? surfaceSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? accent,
    Color? error,
  }) {
    return NexusColors(
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      error: error ?? this.error,
    );
  }

  @override
  NexusColors lerp(ThemeExtension<NexusColors>? other, double t) {
    if (other is! NexusColors) return this;
    return NexusColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

extension NexusThemeContext on BuildContext {
  NexusColors get nexusColors =>
      Theme.of(this).extension<NexusColors>() ?? NexusColors.light;

  TextTheme get textTheme => Theme.of(this).textTheme;
}

