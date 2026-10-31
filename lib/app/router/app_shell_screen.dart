import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/app.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';
import 'package:nexusbo/features/news/presentation/screens/article_detail_screen.dart';
import 'package:nexusbo/features/news/presentation/screens/news_feed_screen.dart';
import 'package:nexusbo/features/reports/presentation/providers/reports_provider.dart';
import 'package:nexusbo/features/reports/presentation/screens/reports_screen.dart';
import 'package:nexusbo/features/search/presentation/screens/search_screen.dart';
import 'package:nexusbo/features/settings/presentation/providers/settings_provider.dart';
import 'package:nexusbo/features/settings/presentation/screens/settings_screen.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';

/// Contenedor de navegación principal con barra inferior editorial de 4 secciones:
/// Inicio, Buscar, Guardados y Ajustes.
///
/// Gestiona además la navegación desde notificaciones locales (tanto cuando la
/// aplicación está abierta/en background como en cold start).
class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key});

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  static const List<Widget> _pages = <Widget>[
    NewsFeedScreen(),
    SearchScreen(),
    ReportsScreen(),
    FavoritesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Esperar al primer frame para garantizar que MaterialApp, NavigatorState y
    // los providers de Riverpod estén listos antes de procesar un tap de cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Inicializar el estado de preferencias/worker al arrancar
      ref.read(settingsProvider);
      NotificationService.instance.setPayloadTapHandler(
        _handleNotificationPayloadTap,
      );
    });
  }

  @override
  void dispose() {
    NotificationService.instance.setPayloadTapHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(ref.read(settingsProvider.notifier).refreshPermissionStatus());
      unawaited(ref.read(newsFeedProvider.notifier).reloadFromSqlite());
    }
  }

  Future<void> _handleNotificationPayloadTap(String rawPayload) async {
    if (!mounted) return;
    final parsedPayload = AppNotificationPayload.parse(rawPayload);
    final navigator = appNavigatorKey.currentState;
    navigator?.popUntil((route) => route.isFirst);

    if (parsedPayload is ReportNotificationPayload) {
      setState(() {
        _currentIndex = 2; // Pestaña Reportes
      });
      await ref.read(reportsProvider.notifier).setWindowFromNotification(
            startUtc: parsedPayload.startUtc,
            endUtc: parsedPayload.endUtc,
          );
      return;
    }

    if (parsedPayload is ArticleNotificationPayload) {
      setState(() {
        _currentIndex = 0;
      });
      await ref.read(newsFeedProvider.notifier).reloadFromSqlite();

      try {
        final article = await ref
            .read(newsRepositoryProvider)
            .getArticleById(parsedPayload.articleId);
        if (!mounted || article == null) return;

        navigator?.push(
          MaterialPageRoute<void>(
            builder: (_) => ArticleDetailScreen(article: article),
          ),
        );
      } catch (_) {
        // Fallback seguro en Home
      }
      return;
    }

    // Default: Home
    setState(() {
      _currentIndex = 0;
    });
    await ref.read(newsFeedProvider.notifier).reloadFromSqlite();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.border,
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.newspaper_outlined),
              selectedIcon: Icon(Icons.newspaper),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Buscar',
            ),
            NavigationDestination(
              icon: Icon(Icons.summarize_outlined),
              selectedIcon: Icon(Icons.summarize),
              label: 'Reportes',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border_rounded),
              selectedIcon: Icon(Icons.bookmark_rounded),
              label: 'Favoritos',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}
