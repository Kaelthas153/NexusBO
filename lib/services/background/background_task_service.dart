import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/sources/abi_news_source.dart';
import 'package:nexusbo/features/news/data/sources/dtv_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_deber_news_source.dart';
import 'package:nexusbo/features/news/data/sources/la_razon_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_diario_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_pais_news_source.dart';
import 'package:nexusbo/features/news/data/sources/correo_del_sur_news_source.dart';
import 'package:nexusbo/features/news/data/sources/unitel_news_source.dart';
import 'package:nexusbo/features/news/data/sources/anf_news_source.dart';
import 'package:nexusbo/features/news/data/repositories/news_repository_impl.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/entities/sync_result.dart';
import 'package:nexusbo/features/news/domain/repositories/news_repository.dart';
import 'package:nexusbo/features/news/domain/sources/multi_source_sync_engine.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';
import 'package:nexusbo/features/reports/domain/services/monitoring_report_service.dart';
import 'package:nexusbo/services/database/app_database.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';
import 'package:nexusbo/services/preferences/app_preferences_service.dart';

/// Resultado semántico para informar a Android WorkManager cómo concluyó la
/// tarea de sincronización en segundo plano.
enum BackgroundTaskOutcome {
  /// Sincronización completada con éxito (`Result.success()`).
  success,

  /// Fallo temporal de red (`Result.retry()` con backoff exponencial).
  retry,

  /// Fallo permanente o de formato (`Result.failure()` sin bucle de reintentos).
  failure,
}

/// Resumen estructurado de una ejecución de sincronización en segundo plano.
@immutable
class BackgroundSyncExecutionResult {
  const BackgroundSyncExecutionResult({
    required this.outcome,
    required this.fetchedCount,
    required this.insertedCount,
    required this.notifiableArticles,
    required this.notificationsDispatched,
    required this.prunedCount,
    required this.wasInitialOrPostClearSeed,
    this.errorMessage,
  });

  final BackgroundTaskOutcome outcome;
  final int fetchedCount;
  final int insertedCount;
  final List<Article> notifiableArticles;
  final bool notificationsDispatched;
  final int prunedCount;
  final bool wasInitialOrPostClearSeed;
  final String? errorMessage;

  int get notifiedArticlesCount =>
      notificationsDispatched ? notifiableArticles.length : 0;
}

/// Orquestador puro de sincronización en segundo plano.
///
/// No depende de Riverpod, `BuildContext` ni widgets. Reutiliza exactamente el
/// mismo [NewsRepository.syncLatestArticles] que el foreground, pero aplica la
/// política de notificaciones locales y el pruning posterior.
class BackgroundSyncOrchestrator {
  BackgroundSyncOrchestrator({
    required NewsRepository repository,
    required AppPreferencesDataSource preferences,
    required NotificationGateway notificationGateway,
  }) : _repository = repository,
       _preferences = preferences,
       _notificationGateway = notificationGateway;

  final NewsRepository _repository;
  final AppPreferencesDataSource _preferences;
  final NotificationGateway _notificationGateway;

  /// Ejecuta el ciclo completo de sincronización background:
  /// 1. Verifica si SQLite estaba vacía antes de sincronizar o si se acaba de
  ///    limpiar la caché.
  /// 2. Sincroniza con ABI mediante [NewsRepository.syncLatestArticles].
  /// 3. Detecta artículos realmente nuevos (`syncResult.newArticles`).
  /// 4. Si no era carga inicial/post-borrado y `notificationsEnabled == true`,
  ///    muestra notificaciones locales (individual, agrupadas o resumen).
  /// 5. Ejecuta el pruning de artículos no favoritos mayores a 30 días.
  Future<BackgroundSyncExecutionResult> executeBackgroundSync() async {
    try {
      final backgroundSyncEnabled = await _preferences.getBackgroundSyncEnabled(
        reload: true,
      );
      if (!backgroundSyncEnabled) {
        return const BackgroundSyncExecutionResult(
          outcome: BackgroundTaskOutcome.success,
          fetchedCount: 0,
          insertedCount: 0,
          notifiableArticles: <Article>[],
          notificationsDispatched: false,
          prunedCount: 0,
          wasInitialOrPostClearSeed: false,
        );
      }

      final notificationsEnabled = await _preferences.getNotificationsEnabled(
        reload: true,
      );
      final existingBefore = await _repository.getLatestArticles(limit: 1);
      final wasDatabaseEmptyBeforeSync = existingBefore.isEmpty;
      final wasCacheClearedPendingBaseline = await _preferences
          .isCacheClearedPendingBaseline(reload: true);

      final syncResult = await _repository.syncLatestArticles();

      if (syncResult.fetched > 0 && wasCacheClearedPendingBaseline) {
        await _preferences.setCacheClearedPendingBaseline(false);
        await _preferences.clearSeededSources();
      }

      final isInitialOrPostClearSeed =
          wasDatabaseEmptyBeforeSync || wasCacheClearedPendingBaseline;

      final seededSourceIds =
          await _preferences.getSeededSourceIds(reload: true);
      final List<Article> notifiableArticles;

      if (isInitialOrPostClearSeed) {
        notifiableArticles = const <Article>[];
        // Registrar fuentes presentes como sembradas
        for (final article in syncResult.newArticles) {
          final sId = article.sourceId.toLowerCase();
          if (!seededSourceIds.contains(sId)) {
            await _preferences.setSourceSeeded(sId);
            seededSourceIds.add(sId);
          }
        }
      } else {
        // Protección seed por fuente individual para fuentes añadidas recientemente
        final qualified = <Article>[];
        for (final article in syncResult.newArticles) {
          final sId = article.sourceId.toLowerCase();
          if (!seededSourceIds.contains(sId)) {
            // Primera sincronización de este medio: actúa como seed silencioso
            await _preferences.setSourceSeeded(sId);
            seededSourceIds.add(sId);
          } else {
            qualified.add(article);
          }
        }
        notifiableArticles = qualified;
      }

      var notificationsDispatched = false;
      if (notificationsEnabled && notifiableArticles.isNotEmpty) {
        await _notificationGateway.notifyNewArticles(notifiableArticles);
        notificationsDispatched = true;
      }

      // Verificar y emitir notificación de reporte horario si corresponde
      await _checkAndDispatchHourlyReportNotification(
        syncResult: syncResult,
      );

      // Ejecutar pruning de noticias mayores a 30 días (conservando favoritas)
      // únicamente después de procesar y notificar las noticias nuevas.
      final prunedCount = await _repository.pruneOldArticles();

      return BackgroundSyncExecutionResult(
        outcome: BackgroundTaskOutcome.success,
        fetchedCount: syncResult.fetched,
        insertedCount: syncResult.inserted,
        notifiableArticles: notifiableArticles,
        notificationsDispatched: notificationsDispatched,
        prunedCount: prunedCount,
        wasInitialOrPostClearSeed: isInitialOrPostClearSeed,
      );
    } on NetworkException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'NexusBO [BackgroundSync]: Error temporal de red (se solicitará retry): $e',
        );
      }
      return BackgroundSyncExecutionResult(
        outcome: BackgroundTaskOutcome.retry,
        fetchedCount: 0,
        insertedCount: 0,
        notifiableArticles: const <Article>[],
        notificationsDispatched: false,
        prunedCount: 0,
        wasInitialOrPostClearSeed: false,
        errorMessage: e.message,
      );
    } on AppException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'NexusBO [BackgroundSync]: Error permanente/datos (sin retry agresivo): $e',
        );
      }
      return BackgroundSyncExecutionResult(
        outcome: BackgroundTaskOutcome.failure,
        fetchedCount: 0,
        insertedCount: 0,
        notifiableArticles: const <Article>[],
        notificationsDispatched: false,
        prunedCount: 0,
        wasInitialOrPostClearSeed: false,
        errorMessage: e.message,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NexusBO [BackgroundSync]: Error inesperado: $e');
      }
      return BackgroundSyncExecutionResult(
        outcome: BackgroundTaskOutcome.failure,
        fetchedCount: 0,
        insertedCount: 0,
        notifiableArticles: const <Article>[],
        notificationsDispatched: false,
        prunedCount: 0,
        wasInitialOrPostClearSeed: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Verifica si la última hora completa aún no ha sido notificada y emite
  /// la notificación horaria correspondiente si [hourlyReportsEnabled] está activo.
  Future<bool> _checkAndDispatchHourlyReportNotification({
    required SyncResult syncResult,
    DateTime? referenceUtc,
    bool force = false,
  }) async {
    final hourlyEnabled =
        await _preferences.getHourlyReportsEnabled(reload: true);
    if (!hourlyEnabled && !force) {
      return false;
    }

    // Si todas las fuentes fallaron en este ciclo, posponer notificación
    if (syncResult.fetched == 0 && syncResult.warning != null && !force) {
      return false;
    }

    final window = MonitoringReportService.calculateLastCompleteHourWindow(
      referenceUtc: referenceUtc,
    );

    if (!force) {
      final lastNotified =
          await _preferences.getLastHourlyReportWindowNotified(reload: true);
      if (lastNotified == window.windowId) {
        return false;
      }
    }

    final isAll = await _preferences.getReportSourcesModeAll(reload: true);
    final selectedIds =
        await _preferences.getReportSelectedSourceIds(reload: true);

    final targetSourceIds = (isAll || selectedIds.isEmpty)
        ? const <String>[
            'abi',
            'dtv',
            'eldeber',
            'larazon',
            'eldiario',
            'elpais',
          ]
        : selectedIds;

    final articles = await _repository.getArticlesForReport(
      startUtc: window.startUtc,
      endUtc: window.endUtc,
      sourceIds: targetSourceIds,
    );

    final windowLabel =
        '${BoliviaDateFormatter.format12Hour(window.startBolivia)} - ${BoliviaDateFormatter.format12Hour(window.endBolivia)}';

    await _notificationGateway.showHourlyReportNotification(
      windowLabel: windowLabel,
      articleCount: articles.length,
      startUtc: window.startUtc,
      endUtc: window.endUtc,
    );

    await _preferences.setLastHourlyReportWindowNotified(window.windowId);
    return true;
  }

  /// Dispara manualmente la comprobación de reporte horario para depuración.
  Future<bool> triggerHourlyReportCheckNow({
    DateTime? referenceUtc,
    bool force = false,
  }) async {
    return _checkAndDispatchHourlyReportNotification(
      syncResult: SyncResult(
        fetched: 1,
        inserted: 0,
        syncedAt: DateTime.now().toUtc(),
      ),
      referenceUtc: referenceUtc,
      force: force,
    );
  }
}

/// Entry-point de nivel superior invocado por Android WorkManager en un isolate
/// independiente sin UI ni Riverpod.
@pragma('vm:entry-point')
void nexusBoCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (taskName != BackgroundTaskService.backgroundSyncTaskName) {
      return true;
    }

    final result = await BackgroundTaskService.instance
        .executeIsolatedBackgroundSync(isBackgroundIsolate: true);

    switch (result.outcome) {
      case BackgroundTaskOutcome.success:
        return true;
      case BackgroundTaskOutcome.retry:
        return false;
      case BackgroundTaskOutcome.failure:
        throw StateError(
          result.errorMessage ?? 'Fallo permanente en nexusbo.backgroundSync',
        );
    }
  });
}

/// Servicio para inicializar Android WorkManager y administrar el registro
/// único de la tarea periódica `nexusbo.backgroundSync`.
class BackgroundTaskService {
  BackgroundTaskService._internal();

  static final BackgroundTaskService instance =
      BackgroundTaskService._internal();

  /// Nombre lógico de la tarea recibida por [nexusBoCallbackDispatcher].
  static const String backgroundSyncTaskName = 'nexusbo.backgroundSync';

  /// Nombre único del PeriodicWorkRequest en Android WorkManager.
  static const String backgroundSyncUniqueName =
      'nexusbo.backgroundSync.periodic';

  /// Frecuencia objetivo aproximada (~60 minutos cuando Android lo permita).
  static const Duration periodicFrequency = Duration(minutes: 60);

  /// Retardo base para backoff exponencial cuando falla la red temporalmente.
  static const Duration retryBackoffDelay = Duration(minutes: 15);

  bool _isInitialized = false;

  /// Inicializa el plugin WorkManager con el entry-point de nivel superior.
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await Workmanager().initialize(nexusBoCallbackDispatcher);
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'NexusBO: Workmanager initialization skipped or not available: $e',
        );
      }
    }
  }

  /// Registra o conserva una única tarea periódica (~60 min) con restricción
  /// `NetworkType.connected` y política `ExistingPeriodicWorkPolicy.keep`.
  Future<void> registerUniquePeriodicSync() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await initialize();

    try {
      await Workmanager().registerPeriodicTask(
        backgroundSyncUniqueName,
        backgroundSyncTaskName,
        frequency: periodicFrequency,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: retryBackoffDelay,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'NexusBO: Error al registrar tarea periódica en WorkManager: $e',
        );
      }
    }
  }

  /// Cancela exclusivamente la tarea periódica de sincronización de noticias,
  /// sin utilizar `cancelAll()`.
  Future<void> cancelPeriodicSync() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await initialize();
    try {
      await Workmanager().cancelByUniqueName(backgroundSyncUniqueName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'NexusBO: Error al cancelar tarea periódica en WorkManager: $e',
        );
      }
    }
  }

  /// Consulta a Android WorkManager si la tarea única se encuentra programada.
  Future<bool> isPeriodicSyncScheduled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    await initialize();
    try {
      return await Workmanager().isScheduledByUniqueName(
        backgroundSyncUniqueName,
      );
    } catch (_) {
      return false;
    }
  }

  /// Construye explícitamente las dependencias mínimas (sin Riverpod ni UI) y
  /// ejecuta el mismo flujo que corre dentro del worker de background.
  Future<BackgroundSyncExecutionResult> executeIsolatedBackgroundSync({
    bool isBackgroundIsolate = false,
  }) async {
    final appDatabase = AppDatabase.instance;
    final localDataSource = SqliteNewsLocalDataSource(appDatabase: appDatabase);
    final dioClient = DioClient();
    final registry = NewsSourceRegistry(
      initialSources: <NewsSource>[
        AbiNewsSource(dioClient: dioClient),
        DtvNewsSource(dioClient: dioClient),
        ElDeberNewsSource(dioClient: dioClient),
        LaRazonNewsSource(
          dioClient: dioClient,
          localDataSource: localDataSource,
        ),
        ElDiarioNewsSource(dioClient: dioClient),
        ElPaisNewsSource(
          dioClient: dioClient,
          localDataSource: localDataSource,
        ),
        CorreoDelSurNewsSource(
          dioClient: dioClient,
          localDataSource: localDataSource,
        ),
        UnitelNewsSource(
          dioClient: dioClient,
          localDataSource: localDataSource,
        ),
        AnfNewsSource(
          dioClient: dioClient,
          localDataSource: localDataSource,
        ),
      ],
    );
    final syncEngine = MultiSourceSyncEngine(
      registry: registry,
      maxConcurrency: 2,
      perSourceTimeout: const Duration(seconds: 10),
    );
    final repository = NewsRepositoryImpl(
      localDataSource: localDataSource,
      syncEngine: syncEngine,
    );
    final preferences = AppPreferencesService();
    final notificationService = NotificationService.instance;

    await notificationService.initialize(
      isBackgroundIsolate: isBackgroundIsolate,
    );

    final orchestrator = BackgroundSyncOrchestrator(
      repository: repository,
      preferences: preferences,
      notificationGateway: notificationService,
    );

    return orchestrator.executeBackgroundSync();
  }

  /// Ejecuta inmediatamente la verificación del reporte horario (para depuración en Settings).
  Future<bool> processHourlyReportNow({bool force = false}) async {
    final appDatabase = AppDatabase.instance;
    final localDataSource = SqliteNewsLocalDataSource(appDatabase: appDatabase);
    final repository = NewsRepositoryImpl(localDataSource: localDataSource);
    final preferences = AppPreferencesService();
    final notificationService = NotificationService.instance;
    await notificationService.initialize();

    final orchestrator = BackgroundSyncOrchestrator(
      repository: repository,
      preferences: preferences,
      notificationGateway: notificationService,
    );

    return orchestrator.triggerHourlyReportCheckNow(force: force);
  }
}
