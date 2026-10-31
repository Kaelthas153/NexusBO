import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/router/app_shell_screen.dart';
import 'package:nexusbo/app/theme/app_theme.dart';
import 'package:nexusbo/app/theme/theme_mode_provider.dart';

/// Clave global de navegación para dirigir al usuario desde notificaciones
/// locales (tanto en primer/segundo plano como en cold start).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Widget raíz de NexusBO configurado con MaterialApp, temas claro/oscuro
/// y navegación principal.
class NexusBoApp extends ConsumerWidget {
  const NexusBoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'NexusBO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const AppShellScreen(),
    );
  }
}
