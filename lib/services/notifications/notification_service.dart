import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';

/// Tipo de estrategia aplicada según la cantidad de noticias nuevas detectadas.
enum NotificationGroupingStrategy {
  none,
  single,
  groupedIndividuals,
  digestSummary,
}

/// Representación inmutable de una notificación individual o resumen lista para
/// mostrarse en Android y verificarse en pruebas unitarias.
@immutable
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    this.groupKey,
    this.isGroupSummary = false,
    this.inboxLines = const <String>[],
    this.expandedSummaryText,
  });

  final int id;
  final String title;
  final String body;
  final String payload;
  final String? groupKey;
  final bool isGroupSummary;
  final List<String> inboxLines;
  final String? expandedSummaryText;
}

/// Plan de notificaciones calculado a partir de una lista de artículos nuevos.
@immutable
class NotificationDispatchPlan {
  const NotificationDispatchPlan({
    required this.strategy,
    required this.notifications,
  });

  final NotificationGroupingStrategy strategy;
  final List<PlannedNotification> notifications;

  bool get isEmpty => notifications.isEmpty;
}

/// Contrato de notificaciones para desacoplar el orquestador de background
/// de los canales nativos durante pruebas automatizadas.
abstract interface class NotificationGateway {
  Future<void> initialize({bool isBackgroundIsolate = false});

  Future<void> notifyNewArticles(List<Article> newArticles);

  Future<void> showHourlyReportNotification({
    required String windowLabel,
    required int articleCount,
    required DateTime startUtc,
    required DateTime endUtc,
  });

  Future<void> showDebugTestNotification();
}

/// Helper para codificación y decodificación de payloads de notificación en NexusBO.
sealed class AppNotificationPayload {
  const AppNotificationPayload();

  static const String homePrefix = 'home';
  static const String articlePrefix = 'article:';
  static const String reportPrefix = 'report:';

  static AppNotificationPayload parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const HomeNotificationPayload();
    }
    final trimmed = raw.trim();
    if (trimmed == 'nexusbo:home' ||
        trimmed == 'nexusbo:test_home' ||
        trimmed == 'home') {
      return const HomeNotificationPayload();
    }
    if (trimmed.startsWith(articlePrefix)) {
      final id = trimmed.substring(articlePrefix.length).trim();
      return id.isNotEmpty
          ? ArticleNotificationPayload(id)
          : const HomeNotificationPayload();
    }
    if (trimmed.startsWith(reportPrefix)) {
      final parts = trimmed.substring(reportPrefix.length).split(':');
      if (parts.length >= 2) {
        final startMs = int.tryParse(parts[0]);
        final endMs = int.tryParse(parts[1]);
        if (startMs != null && endMs != null) {
          return ReportNotificationPayload(
            startUtc: DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
            endUtc: DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
          );
        }
      }
      return const HomeNotificationPayload();
    }
    // Compatibilidad: si es un ID de artículo sin prefijo
    return ArticleNotificationPayload(trimmed);
  }
}

class HomeNotificationPayload extends AppNotificationPayload {
  const HomeNotificationPayload();
}

class ArticleNotificationPayload extends AppNotificationPayload {
  const ArticleNotificationPayload(this.articleId);
  final String articleId;
}

class ReportNotificationPayload extends AppNotificationPayload {
  const ReportNotificationPayload({
    required this.startUtc,
    required this.endUtc,
  });
  final DateTime startUtc;
  final DateTime endUtc;
}

/// Servicio centralizado de notificaciones locales para Android.
class NotificationService implements NotificationGateway {
  NotificationService._internal({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static final NotificationService instance = NotificationService._internal();

  /// Canal Android estable para noticias de NexusBO.
  static const String channelId = 'nexusbo_news';
  static const String channelName = 'Noticias de NexusBO';
  static const String channelDescription =
      'Notificaciones de nuevas noticias detectadas por NexusBO.';

  /// Canal Android para avisos de reportes de monitoreo por rango horario.
  static const String reportsChannelId = 'nexusbo_reports';
  static const String reportsChannelName = 'Reportes de monitoreo';
  static const String reportsChannelDescription =
      'Avisos cuando un reporte horario de noticias está disponible.';

  /// Clave de agrupación Android para 2 o 3 noticias nuevas simultáneas.
  static const String newsGroupKey = 'com.nexusbo.app.NEWS_GROUP';

  /// Payloads reservados para navegación a portada (Home).
  static const String homePayload = 'nexusbo:home';
  static const String testPayload = 'nexusbo:test_home';

  /// IDs reservados fuera del rango de artículos individuales.
  static const int groupSummaryNotificationId = 1000;
  static const int digestSummaryNotificationId = 1001;
  static const int debugTestNotificationId = 1002;
  static const int hourlyReportNotificationId = 1003;

  final FlutterLocalNotificationsPlugin _plugin;

  bool _isInitializedForeground = false;
  bool _isInitializedBackground = false;
  bool _channelCreated = false;
  bool _hasCheckedColdStartLaunch = false;

  String? _pendingTapPayload;
  FutureOr<void> Function(String payload)? _onPayloadTapHandler;

  /// Calcula un ID entero positivo (31 bits) determinista y estable a partir
  /// del [articleId] usando FNV-1a, evitando `String.hashCode` y evitando
  /// colisiones con `0` o con los IDs reservados (`1000..9999`).
  static int stableNotificationIdForArticle(String articleId) {
    final normalized = articleId.trim();
    final bytes = utf8.encode(normalized.isEmpty ? 'nexusbo_default' : normalized);
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    // Asegurar rango [10000, 0x7fffffff] para no colisionar con IDs reservados ni con 0
    if (hash < 10000) {
      hash += 10000;
    }
    return hash;
  }

  /// Construye de manera pura el plan de notificaciones siguiendo las reglas:
  /// - 0 noticias nuevas -> ninguna notificación.
  /// - 1 noticia nueva -> 1 notificación individual con payload = `article.id`.
  /// - 2 o 3 noticias nuevas -> notificaciones individuales agrupadas (`groupKey`)
  ///   más resumen de grupo de Android.
  /// - >3 noticias nuevas -> 1 única notificación resumen (`InboxStyle`) con
  ///   payload = [homePayload] para evitar spam.
  static NotificationDispatchPlan buildDispatchPlan(List<Article> newArticles) {
    if (newArticles.isEmpty) {
      return const NotificationDispatchPlan(
        strategy: NotificationGroupingStrategy.none,
        notifications: <PlannedNotification>[],
      );
    }

    if (newArticles.length == 1) {
      final article = newArticles.first;
      return NotificationDispatchPlan(
        strategy: NotificationGroupingStrategy.single,
        notifications: <PlannedNotification>[
          PlannedNotification(
            id: stableNotificationIdForArticle(article.id),
            title: article.title,
            body: _formatSingleNotificationBody(article),
            payload: article.id,
            expandedSummaryText: article.summary,
          ),
        ],
      );
    }

    if (newArticles.length <= 3) {
      final items = <PlannedNotification>[
        for (final article in newArticles)
          PlannedNotification(
            id: stableNotificationIdForArticle(article.id),
            title: article.title,
            body: _formatSingleNotificationBody(article),
            payload: article.id,
            groupKey: newsGroupKey,
            expandedSummaryText: article.summary,
          ),
        PlannedNotification(
          id: groupSummaryNotificationId,
          title: '${newArticles.length} noticias nuevas en NexusBO',
          body: 'Nuevas noticias publicadas en NexusBO. Toca para verlas.',
          payload: homePayload,
          groupKey: newsGroupKey,
          isGroupSummary: true,
          inboxLines: newArticles
              .map((a) => a.title)
              .toList(growable: false),
        ),
      ];

      return NotificationDispatchPlan(
        strategy: NotificationGroupingStrategy.groupedIndividuals,
        notifications: items,
      );
    }

    // Más de 3 noticias nuevas: mostrar únicamente 1 notificación resumen
    final count = newArticles.length;
    return NotificationDispatchPlan(
      strategy: NotificationGroupingStrategy.digestSummary,
      notifications: <PlannedNotification>[
        PlannedNotification(
          id: digestSummaryNotificationId,
          title: '$count noticias nuevas en NexusBO',
          body: 'Nuevas noticias publicadas en NexusBO. Toca para verlas.',
          payload: homePayload,
          inboxLines: newArticles
              .take(5)
              .map((a) => a.title)
              .toList(growable: false),
        ),
      ],
    );
  }

  static String _formatSingleNotificationBody(Article article) {
    final source = article.sourceName.trim().isNotEmpty
        ? article.sourceName.trim()
        : 'NexusBO';
    final rawCategory = article.category.trim();
    final category = rawCategory.isNotEmpty
        ? CategoryMapper.toDisplay(rawCategory)
        : 'General';
    return '$source • $category';
  }

  /// Inicializa el plugin y garantiza la existencia del canal Android.
  ///
  /// Cuando [isBackgroundIsolate] es `false`, también configura el callback de
  /// tap en notificaciones e inspecciona si la app fue iniciada desde una
  /// notificación con la aplicación cerrada (cold start).
  @override
  Future<void> initialize({bool isBackgroundIsolate = false}) async {
    if (!isBackgroundIsolate && _isInitializedForeground) {
      return;
    }
    if (isBackgroundIsolate &&
        (_isInitializedBackground || _isInitializedForeground)) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: isBackgroundIsolate
          ? null
          : _handleNotificationResponse,
    );

    await _ensureAndroidChannelCreated();

    if (isBackgroundIsolate) {
      _isInitializedBackground = true;
    } else {
      _isInitializedForeground = true;
      await _captureColdStartLaunchPayloadIfNeeded();
    }
  }

  Future<void> _ensureAndroidChannelCreated() async {
    if (_channelCreated) return;
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );
    await androidPlugin.createNotificationChannel(channel);

    const reportsChannel = AndroidNotificationChannel(
      reportsChannelId,
      reportsChannelName,
      description: reportsChannelDescription,
      importance: Importance.defaultImportance,
    );
    await androidPlugin.createNotificationChannel(reportsChannel);

    _channelCreated = true;
  }

  Future<void> _captureColdStartLaunchPayloadIfNeeded() async {
    if (_hasCheckedColdStartLaunch) return;
    _hasCheckedColdStartLaunch = true;

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final payload = launchDetails.notificationResponse?.payload?.trim();
        if (payload != null && payload.isNotEmpty) {
          _dispatchOrQueueTapPayload(payload);
        } else {
          _dispatchOrQueueTapPayload(homePayload);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NexusBO: Error al consultar launch details de notificación: $e');
      }
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload?.trim();
    if (payload == null || payload.isEmpty) {
      _dispatchOrQueueTapPayload(homePayload);
      return;
    }
    _dispatchOrQueueTapPayload(payload);
  }

  void _dispatchOrQueueTapPayload(String payload) {
    final handler = _onPayloadTapHandler;
    if (handler != null) {
      handler(payload);
    } else {
      _pendingTapPayload = payload;
    }
  }

  /// Registra el manejador de navegación cuando el árbol de widgets y el
  /// [NavigatorState] están listos. Si había un tap pendiente de cold start,
  /// lo entrega inmediatamente una sola vez.
  void setPayloadTapHandler(FutureOr<void> Function(String payload)? handler) {
    _onPayloadTapHandler = handler;
    final pending = _pendingTapPayload;
    if (handler != null && pending != null) {
      _pendingTapPayload = null;
      handler(pending);
    }
  }

  /// Solicita el permiso `POST_NOTIFICATIONS` en Android 13+ desde la UI.
  /// En versiones anteriores de Android donde no se requiere permiso en tiempo
  /// de ejecución, devuelve `true` si las notificaciones están habilitadas.
  Future<bool> requestPermissionFromUi() async {
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return false;
    }

    try {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted != null) {
        return granted;
      }
      final enabled = await androidPlugin.areNotificationsEnabled();
      return enabled ?? true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NexusBO: Error al solicitar permiso de notificaciones: $e');
      }
      return false;
    }
  }

  /// Verifica si el permiso de notificaciones sigue activo en el sistema Android.
  Future<bool> areNotificationsAllowedBySystem() async {
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return false;
    }
    try {
      return await androidPlugin.areNotificationsEnabled() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Muestra las notificaciones correspondientes a [newArticles] siguiendo la
  /// política anti-spam de NexusBO.
  @override
  Future<void> notifyNewArticles(List<Article> newArticles) async {
    final plan = buildDispatchPlan(newArticles);
    if (plan.isEmpty) return;

    await initialize(
      isBackgroundIsolate: !_isInitializedForeground,
    );

    final allowed = await areNotificationsAllowedBySystem();
    if (!allowed) return;

    for (final item in plan.notifications) {
      final styleInfo = item.inboxLines.isNotEmpty
          ? InboxStyleInformation(
              item.inboxLines,
              contentTitle: item.title,
              summaryText: 'ABI • Nuevos despachos',
            )
          : (item.expandedSummaryText != null &&
                    item.expandedSummaryText!.trim().isNotEmpty
                ? BigTextStyleInformation(
                    item.expandedSummaryText!,
                    contentTitle: item.title,
                    summaryText: item.body,
                  )
                : null);

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        groupKey: item.groupKey,
        setAsGroupSummary: item.isGroupSummary,
        groupAlertBehavior: item.groupKey != null
            ? GroupAlertBehavior.summary
            : GroupAlertBehavior.all,
        styleInformation: styleInfo,
        autoCancel: true,
      );

      await _plugin.show(
        id: item.id,
        title: item.title,
        body: item.body,
        notificationDetails: NotificationDetails(android: androidDetails),
        payload: item.payload,
      );
    }
  }

  /// Emite una notificación informando que el reporte de monitoreo de la última
  /// hora completa está disponible para revisión y copia a portapapeles.
  @override
  Future<void> showHourlyReportNotification({
    required String windowLabel,
    required int articleCount,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    await initialize(
      isBackgroundIsolate: !_isInitializedForeground,
    );

    final allowed = await areNotificationsAllowedBySystem();
    if (!allowed) return;

    final payload =
        'report:${startUtc.millisecondsSinceEpoch}:${endUtc.millisecondsSinceEpoch}';

    const androidDetails = AndroidNotificationDetails(
      reportsChannelId,
      reportsChannelName,
      channelDescription: reportsChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    final title = 'Reporte de monitoreo listo';
    final countLabel =
        articleCount == 1 ? '1 noticia' : '$articleCount noticias';
    final body = '$windowLabel • $countLabel';

    await _plugin.show(
      id: hourlyReportNotificationId,
      title: title,
      body: body,
      notificationDetails:
          const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  /// Lanza una notificación de prueba en modo DEBUG sin insertar datos falsos
  /// en SQLite. Al tocarla, abre la portada (Home) de NexusBO.
  @override
  Future<void> showDebugTestNotification() async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );

    await _plugin.show(
      id: debugTestNotificationId,
      title: 'Notificación de prueba · NexusBO',
      body: 'Canal nexusbo_news operativo. Toca para abrir la portada.',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: testPayload,
    );
  }
}

