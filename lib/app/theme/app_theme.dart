import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/app/theme/app_typography.dart';

/// Configuración de ThemeData para modo claro y oscuro de NexusBO.
/// Utiliza Material 3 despojando elevaciones artificiales, tintes automáticos
/// y bordes redondeados excesivos para lograr una estética editorial sobria.
abstract final class AppTheme {
  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        colors: NexusColors.light,
      );

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        colors: NexusColors.dark,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required NexusColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    final textTheme = AppTypography.buildTextTheme(colors);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: isDark ? const Color(0xFF062026) : Colors.white,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: isDark ? Colors.white : AppColors.lightPrimaryDark,
      secondary: colors.accent,
      onSecondary: isDark ? const Color(0xFF062026) : Colors.white,
      secondaryContainer: colors.surfaceSecondary,
      onSecondaryContainer: colors.textPrimary,
      error: colors.error,
      onError: Colors.white,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.border,
      outlineVariant: colors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.surfaceSecondary.withValues(alpha: 0.45),
      dividerColor: colors.border,
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: colors.surface,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: colors.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.1,
            color: isSelected ? colors.primary : colors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? colors.primary : colors.textSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colors.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? const Color(0xFF062026) : Colors.white;
          }
          return colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primary;
          }
          return colors.surfaceSecondary;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colors.border;
        }),
      ),
    );
  }
}

