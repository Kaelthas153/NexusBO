import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/datasources/news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/data/repositories/news_repository_impl.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/services/background/background_task_service.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';
import 'package:nexusbo/services/preferences/app_preferences_service.dart';

void main() {
  group('Etapa 4: Background Sync Orchestrator y Notificaciones Locales (Puntos A - H)', () {
    late _InMemoryNewsLocalDataSource localDataSource;
    late _FakeNewsRemoteDataSource remoteDataSource;
    late NewsRepositoryImpl repository;
    late AppPreferencesService preferences;
    late _RecordingNotificationGateway notificationGateway;
    late BackgroundSyncOrchestrator orchestrator;

    ArticleModel buildArticleModel(
      int index, {
      String? customTitle,
      DateTime? publishedAt,
    }) {
      final pub = publishedAt ??
          DateTime.utc(2026, 10, 31, 12, 0).subtract(Duration(minutes: index));
      return ArticleModel(
        id: 'abi_${42000 + index}',
        title: customTitle ?? 'Titular ABI #$index',
        summary: 'Resumen limpio del despacho #$index.',
        contentPlain: 'Contenido completo del despacho #$index.',
        url: 'https://abi.bo/noticia-$index/',
        imageUrl: 'https://abi.bo/wp-content/uploads/2026/10/img_$index.jpg',
        imageUrls: <String>[
          'https://abi.bo/wp-content/uploads/2026/10/img_$index.jpg',
        ],
        author: 'Redacción Central',
        sourceId: 'abi',
        sourceName: 'ABI',
        category: index.isEven ? 'Política' : 'Economía',
        tags: const <String>['Bolivia'],
        publishedAt: pub,
        fetchedAt: DateTime.utc(2026, 10, 31, 12, 5),
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppPreferencesService.keyNotificationsEnabled: true,
      });
      localDataSource = _InMemoryNewsLocalDataSource();
      remoteDataSource = _FakeNewsRemoteDataSource();
      repository = NewsRepositoryImpl(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );
      preferences = AppPreferencesService();
      notificationGateway = _RecordingNotificationGateway();
      orchestrator = BackgroundSyncOrchestrator(
        repository: repository,
        preferences: preferences,
        notificationGateway: notificationGateway,
      );
    });

    test(
      'A, B, C, D: Base vacía (0 notificables) -> +1 nueva (1 notificable) -> mismas 10 (0 notificables) -> conserva favoritas y post-borrado no spamea',
      () async {
        // ---------------------------------------------------------------------
        // A. Base vacía + 10 recibidas: 10 insertadas, 0 notificables
        // ---------------------------------------------------------------------
        final initial10 = List<ArticleModel>.generate(10, buildArticleModel);
        remoteDataSource.nextBatch = initial10;

        final resultA = await orchestrator.executeBackgroundSync();
        expect(resultA.outcome, BackgroundTaskOutcome.success);
        expect(resultA.fetchedCount, 10);
        expect(resultA.insertedCount, 10);
        expect(resultA.wasInitialOrPostClearSeed, isTrue);
        expect(resultA.notifiableArticles, isEmpty);
        expect(resultA.notificationsDispatched, isFalse);
        expect(notificationGateway.dispatchedBatches, isEmpty);

        // Marcar una noticia como favorita antes de las siguientes sincronizaciones (Punto D)
        await repository.toggleFavorite('abi_42000');
        final favBefore = await repository.getArticleById('abi_42000');
        expect(favBefore?.isFavorite, isTrue);

        // ---------------------------------------------------------------------
        // B. Base con 10 + 1 nueva: 1 notificable
        // ---------------------------------------------------------------------
        final batchWith1New = <ArticleModel>[
          buildArticleModel(10, customTitle: 'Noticia 10 recién publicada'),
          ...initial10.take(9),
        ];
        remoteDataSource.nextBatch = batchWith1New;

        final resultB = await orchestrator.executeBackgroundSync();
        expect(resultB.outcome, BackgroundTaskOutcome.success);
        expect(resultB.fetchedCount, 10);
        expect(resultB.insertedCount, 1);
        expect(resultB.wasInitialOrPostClearSeed, isFalse);
        expect(resultB.notifiableArticles.length, 1);
        expect(resultB.notifiableArticles.first.id, 'abi_42010');
        expect(resultB.notificationsDispatched, isTrue);
        expect(notificationGateway.dispatchedBatches.length, 1);
        expect(notificationGateway.dispatchedBatches.single.single.id, 'abi_42010');

        // Total acumulado en SQLite debe ser 11
        final storedAfterB = await repository.getLatestArticles();
        expect(storedAfterB.length, 11);

        // ---------------------------------------------------------------------
        // C. Base con 11 + mismas 10 del feed: 0 notificables
        // ---------------------------------------------------------------------
        remoteDataSource.nextBatch = batchWith1New;
        final resultC = await orchestrator.executeBackgroundSync();
        expect(resultC.outcome, BackgroundTaskOutcome.success);
        expect(resultC.insertedCount, 0);
        expect(resultC.notifiableArticles, isEmpty);
        expect(resultC.notificationsDispatched, isFalse);
        // No se agregó ningún batch adicional de notificaciones
        expect(notificationGateway.dispatchedBatches.length, 1);

        // ---------------------------------------------------------------------
        // D. Base con favoritas: UPSERT conserva favorito intacto
        // ---------------------------------------------------------------------
        final favAfter = await repository.getArticleById('abi_42000');
        expect(favAfter?.isFavorite, isTrue);
        expect(favAfter?.favoritedAt, isNotNull);

        // ---------------------------------------------------------------------
        // Caso Borrar Caché (conservando favorita) + siguiente sync background:
        // NO considerar las 10 descargadas como nuevas para notificación
        // ---------------------------------------------------------------------
        await preferences.setCacheClearedPendingBaseline(true);
        await repository.clearCache(keepFavorites: true);
        final remainingAfterClear = await repository.getLatestArticles();
        expect(remainingAfterClear.length, 1); // Queda solo la favorita

        final resultPostClear = await orchestrator.executeBackgroundSync();
        expect(resultPostClear.outcome, BackgroundTaskOutcome.success);
        expect(resultPostClear.wasInitialOrPostClearSeed, isTrue);
        expect(resultPostClear.notifiableArticles, isEmpty);
        expect(resultPostClear.notificationsDispatched, isFalse);
        expect(await preferences.isCacheClearedPendingBaseline(), isFalse);
      },
    );

    test(
      'E y H: Agrupación de notificaciones (1 individual, 2-3 agrupadas, >3 resumen) y payload con articleId e IDs deterministas',
      () {
        final articles5 = List<Article>.generate(
          5,
          (i) => buildArticleModel(i).toEntity(),
        );

        // 1 noticia -> Individual + payload = articleId
        final plan1 = NotificationService.buildDispatchPlan(
          articles5.take(1).toList(),
        );
        expect(plan1.strategy, NotificationGroupingStrategy.single);
        expect(plan1.notifications.length, 1);
        expect(plan1.notifications.single.payload, 'abi_42000');
        expect(plan1.notifications.single.title, 'Titular ABI #0');
        expect(plan1.notifications.single.body, 'ABI • Política');
        expect(plan1.notifications.single.id, greaterThanOrEqualTo(10000));
        // Determinismo del ID
        expect(
          NotificationService.stableNotificationIdForArticle('abi_42000'),
          equals(plan1.notifications.single.id),
        );
        expect(
          NotificationService.stableNotificationIdForArticle('abi_42000'),
          isNot(equals(NotificationService.stableNotificationIdForArticle('abi_42001'))),
        );

        // 2 o 3 noticias -> Individuales agrupadas + resumen de grupo Android
        final plan3 = NotificationService.buildDispatchPlan(
          articles5.take(3).toList(),
        );
        expect(plan3.strategy, NotificationGroupingStrategy.groupedIndividuals);
        // 3 individuales + 1 group summary = 4 items
        expect(plan3.notifications.length, 4);
        final individualItems = plan3.notifications
            .where((n) => !n.isGroupSummary)
            .toList();
        expect(individualItems.length, 3);
        expect(
          individualItems.map((n) => n.payload).toList(),
          equals(<String>['abi_42000', 'abi_42001', 'abi_42002']),
        );
        for (final item in individualItems) {
          expect(item.groupKey, NotificationService.newsGroupKey);
        }
        final summaryItem = plan3.notifications.singleWhere(
          (n) => n.isGroupSummary,
        );
        expect(summaryItem.id, NotificationService.groupSummaryNotificationId);
        expect(summaryItem.payload, NotificationService.homePayload);

        // >3 noticias (5) -> 1 sola notificación resumen (sin lanzar 5 individuales)
        final plan5 = NotificationService.buildDispatchPlan(articles5);
        expect(plan5.strategy, NotificationGroupingStrategy.digestSummary);
        expect(plan5.notifications.length, 1);
        expect(
          plan5.notifications.single.id,
          NotificationService.digestSummaryNotificationId,
        );
        expect(
          plan5.notifications.single.title,
          '5 noticias nuevas en NexusBO',
        );
        expect(
          plan5.notifications.single.payload,
          NotificationService.homePayload,
        );
        expect(plan5.notifications.single.inboxLines.length, 5);
      },
    );

    test(
      'F: notificationsEnabled == false -> sincroniza SQLite pero NO dispara notificaciones',
      () async {
        // Sembrar base inicial con 2 noticias
        remoteDataSource.nextBatch = <ArticleModel>[
          buildArticleModel(1),
          buildArticleModel(2),
        ];
        await orchestrator.executeBackgroundSync();

        // Desactivar notificaciones en preferencias
        await preferences.setNotificationsEnabled(false);

        // Llega 1 noticia nueva
        remoteDataSource.nextBatch = <ArticleModel>[
          buildArticleModel(3, customTitle: 'Nueva sin permiso'),
          buildArticleModel(1),
          buildArticleModel(2),
        ];

        final result = await orchestrator.executeBackgroundSync();
        expect(result.outcome, BackgroundTaskOutcome.success);
        expect(result.insertedCount, 1);
        expect(result.notifiableArticles.length, 1);
        expect(result.notificationsDispatched, isFalse);
        expect(notificationGateway.dispatchedBatches, isEmpty);
      },
    );

    test(
      'G: Error de red -> datos locales permanecen intactos, outcome == retry y 0 notificaciones',
      () async {
        // Sembrar 3 noticias en SQLite
        remoteDataSource.nextBatch = <ArticleModel>[
          buildArticleModel(1),
          buildArticleModel(2),
          buildArticleModel(3),
        ];
        await orchestrator.executeBackgroundSync();

        // Simular caída de red en la siguiente ejecución de WorkManager
        remoteDataSource.shouldThrowNetworkError = true;

        final result = await orchestrator.executeBackgroundSync();
        expect(result.outcome, BackgroundTaskOutcome.retry);
        expect(result.notificationsDispatched, isFalse);
        expect(notificationGateway.dispatchedBatches, isEmpty);

        final stored = await repository.getLatestArticles();
        expect(stored.length, 3);
      },
    );
  });
}

class _RecordingNotificationGateway implements NotificationGateway {
  final List<List<Article>> dispatchedBatches = <List<Article>>[];
  bool initialized = false;
  int debugTestCalls = 0;

  @override
  Future<void> initialize({bool isBackgroundIsolate = false}) async {
    initialized = true;
  }

  @override
  Future<void> notifyNewArticles(List<Article> newArticles) async {
    dispatchedBatches.add(List<Article>.unmodifiable(newArticles));
  }

  @override
  Future<void> showDebugTestNotification() async {
    debugTestCalls++;
  }

  @override
  Future<void> showHourlyReportNotification({
    required String windowLabel,
    required int articleCount,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {}
}

class _FakeNewsRemoteDataSource implements NewsRemoteDataSource {
  List<ArticleModel> nextBatch = const <ArticleModel>[];
  bool shouldThrowNetworkError = false;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    if (shouldThrowNetworkError) {
      throw const NetworkException('Tiempo de espera agotado al conectar con ABI.');
    }
    return nextBatch;
  }
}

class _InMemoryNewsLocalDataSource implements NewsLocalDataSource {
  final Map<String, ArticleModel> _store = <String, ArticleModel>{};

  @override
  Future<List<ArticleModel>> getLatestArticles({int limit = 100}) async {
    final sorted = _store.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticlesByCategory(
    String category, {
    int limit = 100,
  }) async {
    final all = await getLatestArticles(limit: 1000);
    return all
        .where((a) => a.category.toLowerCase() == category.toLowerCase())
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    var list = await getLatestArticles(limit: 1000);
    if (category != null && category.trim().isNotEmpty && category.toLowerCase() != 'todas') {
      list = list.where((a) => a.category.toLowerCase() == category.toLowerCase()).toList();
    }
    if (sourceId != null && sourceId.trim().isNotEmpty && sourceId.toLowerCase() != 'todas') {
      list = list.where((a) => a.sourceId == sourceId).toList();
    }
    return list.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async {
    final normalizedIds = sourceIds.map((s) => s.trim().toLowerCase()).toSet();
    final list = _store.values.where((article) {
      final pubUtc = article.publishedAt.toUtc();
      final inRange = !pubUtc.isBefore(startUtc) && pubUtc.isBefore(endUtc);
      final inSource = normalizedIds.isEmpty ||
          normalizedIds.contains(article.sourceId.toLowerCase());
      return inRange && inSource;
    }).toList();
    list.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    return list;
  }

  @override
  Future<List<ArticleModel>> searchArticles(
    String query, {
    int limit = 100,
  }) async {
    final all = await getLatestArticles(limit: 1000);
    return all
        .where((a) => a.title.toLowerCase().contains(query.toLowerCase()))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getFavorites() async {
    final all = await getLatestArticles(limit: 1000);
    return all.where((a) => a.isFavorite).toList(growable: false);
  }

  @override
  Future<ArticleModel?> getArticleById(String id) async => _store[id];

  @override
  Future<void> markAsRead(String id) async {
    final current = _store[id];
    if (current != null) {
      _store[id] = current.copyWith(isRead: true);
    }
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final current = _store[id];
    if (current == null) return;
    final nextFav = !current.isFavorite;
    _store[id] = current.copyWith(
      isFavorite: nextFav,
      favoritedAt: nextFav ? DateTime.now().toUtc() : null,
      clearFavoritedAt: !nextFav,
    );
  }

  @override
  Future<List<ArticleModel>> upsertArticles(
    List<ArticleModel> articles,
  ) async {
    final newlyInserted = <ArticleModel>[];
    for (final incoming in articles) {
      final existing = _store[incoming.id];
      if (existing == null) {
        _store[incoming.id] = incoming;
        newlyInserted.add(incoming);
      } else {
        _store[incoming.id] = incoming.copyWith(
          isFavorite: existing.isFavorite,
          favoritedAt: existing.favoritedAt,
          isRead: existing.isRead,
        );
      }
    }
    return newlyInserted;
  }

  @override
  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  }) async {
    final cutoff = (referenceTimeUtc ?? DateTime.now().toUtc()).subtract(
      retentionPeriod,
    );
    final toRemove = _store.values
        .where((a) => !a.isFavorite && a.publishedAt.isBefore(cutoff))
        .map((a) => a.id)
        .toList();
    for (final id in toRemove) {
      _store.remove(id);
    }
    return toRemove.length;
  }

  @override
  Future<int> clearArticles({bool keepFavorites = false}) async {
    if (!keepFavorites) {
      final count = _store.length;
      _store.clear();
      return count;
    }
    final toRemove = _store.values
        .where((a) => !a.isFavorite)
        .map((a) => a.id)
        .toList();
    for (final id in toRemove) {
      _store.remove(id);
    }
    return toRemove.length;
  }
}

