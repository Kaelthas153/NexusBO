import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/datasources/news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/datasources/rss_news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/repositories/news_repository_impl.dart';
import 'package:nexusbo/features/news/data/sources/abi_news_source.dart';
import 'package:nexusbo/features/news/data/sources/dtv_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_deber_news_source.dart';
import 'package:nexusbo/features/news/data/sources/la_razon_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_diario_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_pais_news_source.dart';
import 'package:nexusbo/features/news/data/sources/correo_del_sur_news_source.dart';
import 'package:nexusbo/features/news/data/sources/unitel_news_source.dart';
import 'package:nexusbo/features/news/data/sources/anf_news_source.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/entities/sync_result.dart';
import 'package:nexusbo/features/news/domain/repositories/news_repository.dart';
import 'package:nexusbo/features/news/domain/sources/multi_source_sync_engine.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';
import 'package:nexusbo/features/search/presentation/providers/search_provider.dart';
import 'package:nexusbo/features/settings/presentation/providers/settings_provider.dart';
import 'package:nexusbo/services/database/app_database.dart';

/// Categorías editoriales para filtrar la portada de NexusBO sobre SQLite.
const List<String> kEditorialCategories = <String>[
  'Todas',
  ...ApiConstants.knownMainCategories,
];

// -----------------------------------------------------------------------------
// PROVIDERS DE INFRAESTRUCTURA Y REPOSITORIO
// -----------------------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

final newsLocalDataSourceProvider = Provider<NewsLocalDataSource>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SqliteNewsLocalDataSource(appDatabase: db);
});

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient();
});

final newsRemoteDataSourceProvider = Provider<NewsRemoteDataSource>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  return RssNewsRemoteDataSource(dioClient: dioClient);
});

final newsSourceRegistryProvider = Provider<NewsSourceRegistry>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  final localDataSource = ref.watch(newsLocalDataSourceProvider);
  return NewsSourceRegistry(
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
});

final multiSourceSyncEngineProvider = Provider<MultiSourceSyncEngine>((ref) {
  final registry = ref.watch(newsSourceRegistryProvider);
  return MultiSourceSyncEngine(
    registry: registry,
    maxConcurrency: 2,
    perSourceTimeout: const Duration(seconds: 10),
  );
});

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  final localDataSource = ref.watch(newsLocalDataSourceProvider);
  final remoteDataSource = ref.watch(newsRemoteDataSourceProvider);
  final syncEngine = ref.watch(multiSourceSyncEngineProvider);
  return NewsRepositoryImpl(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    syncEngine: syncEngine,
  );
});

// -----------------------------------------------------------------------------
// ESTADO DE CATEGORÍA ACTIVA
// -----------------------------------------------------------------------------

class SelectedCategoryNotifier extends Notifier<String> {
  @override
  String build() => kEditorialCategories.first;

  void select(String category) {
    if (state == category) return;
    state = category;
  }
}

final selectedCategoryProvider =
    NotifierProvider<SelectedCategoryNotifier, String>(
      SelectedCategoryNotifier.new,
    );

// -----------------------------------------------------------------------------
// ESTADO Y OPCIONES DE FILTRO POR FUENTE
// -----------------------------------------------------------------------------

/// Opción de filtrado por fuente en la portada de NexusBO.
@immutable
class SourceFilterOption {
  const SourceFilterOption({
    required this.displayName,
    this.sourceId,
  });

  final String displayName;

  /// Identificador lógico de la fuente (e.g. `'abi'`, `'dtv'`, `'eldeber'`).
  /// `null` representa "Todas" las fuentes (sin filtro por medio).
  final String? sourceId;

  bool get isAll => sourceId == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceFilterOption &&
          runtimeType == other.runtimeType &&
          displayName == other.displayName &&
          sourceId == other.sourceId;

  @override
  int get hashCode => Object.hash(displayName, sourceId);
}

/// Provider que expone la lista de opciones de fuentes dinámicamente
/// a partir de [NewsSourceRegistry], garantizando extensibilidad futura sin alterar la UI.
final sourceFilterOptionsProvider = Provider<List<SourceFilterOption>>((ref) {
  final registry = ref.watch(newsSourceRegistryProvider);
  final sources = registry.getEnabledSources();
  return <SourceFilterOption>[
    const SourceFilterOption(displayName: 'Todas', sourceId: null),
    ...sources.map(
      (s) => SourceFilterOption(displayName: s.name, sourceId: s.id),
    ),
  ];
});

class SelectedSourceNotifier extends Notifier<String?> {
  @override
  String? build() => null; // null = Todas las fuentes

  void select(String? sourceId) {
    final normalized =
        (sourceId == null ||
            sourceId.trim().isEmpty ||
            sourceId.toLowerCase() == 'todas')
        ? null
        : sourceId.trim();
    if (state == normalized) return;
    state = normalized;
  }
}

final selectedSourceIdProvider =
    NotifierProvider<SelectedSourceNotifier, String?>(
      SelectedSourceNotifier.new,
    );

// -----------------------------------------------------------------------------
// ESTADO Y NOTIFIER DEL FEED PRINCIPAL (OFFLINE-FIRST)
// -----------------------------------------------------------------------------

@immutable
class NewsFeedState {
  const NewsFeedState({
    required this.articles,
    required this.totalCachedCount,
    this.isInitialLoading = false,
    this.isSyncing = false,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.initialErrorMessage,
    this.syncNoticeMessage,
    this.lastSyncedAt,
  });

  /// Lista de artículos de la categoría activa provenientes de SQLite.
  final List<Article> articles;

  /// Cantidad total de artículos almacenados en SQLite (todas las categorías).
  final int totalCachedCount;

  /// `true` únicamente cuando SQLite está vacío y se ejecuta la primera carga.
  final bool isInitialLoading;

  /// `true` mientras se sincroniza con ABI en segundo plano o pull-to-refresh.
  final bool isSyncing;

  /// `true` si existen más artículos en SQLite para paginar.
  final bool hasMore;

  /// `true` mientras se carga la página siguiente desde SQLite.
  final bool isLoadingMore;

  /// Mensaje de error cuando SQLite está vacío y falló la sincronización inicial (Caso D).
  final String? initialErrorMessage;

  /// Aviso discreto cuando hay caché local en SQLite pero falló la actualización (Casos C y E).
  final String? syncNoticeMessage;

  /// Última fecha UTC de sincronización exitosa en la sesión actual.
  final DateTime? lastSyncedAt;

  bool get hasAnyCachedArticles => totalCachedCount > 0;

  NewsFeedState copyWith({
    List<Article>? articles,
    int? totalCachedCount,
    bool? isInitialLoading,
    bool? isSyncing,
    bool? hasMore,
    bool? isLoadingMore,
    String? initialErrorMessage,
    bool clearInitialError = false,
    String? syncNoticeMessage,
    bool clearSyncNotice = false,
    DateTime? lastSyncedAt,
  }) {
    return NewsFeedState(
      articles: articles ?? this.articles,
      totalCachedCount: totalCachedCount ?? this.totalCachedCount,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      initialErrorMessage: clearInitialError
          ? null
          : (initialErrorMessage ?? this.initialErrorMessage),
      syncNoticeMessage: clearSyncNotice
          ? null
          : (syncNoticeMessage ?? this.syncNoticeMessage),
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class NewsFeedNotifier extends Notifier<NewsFeedState> {
  static const int kDefaultPageSize = 50;
  bool _hasTriggeredStartupSync = false;

  @override
  NewsFeedState build() {
    // 1. Iniciar carga inmediata desde SQLite al construir el notifier
    Future<void>.microtask(_initializeOfflineFirst);

    return const NewsFeedState(
      articles: <Article>[],
      totalCachedCount: 0,
      isInitialLoading: true,
      isSyncing: false,
    );
  }

  NewsRepository get _repository => ref.read(newsRepositoryProvider);

  Future<List<Article>> _getFilteredArticles({
    int limit = kDefaultPageSize,
    int offset = 0,
  }) async {
    final category = ref.read(selectedCategoryProvider);
    final sourceId = ref.read(selectedSourceIdProvider);
    return _repository.getArticles(
      category: category == 'Todas' ? null : category,
      sourceId: sourceId,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> _initializeOfflineFirst() async {
    try {
      final allCached = await _repository.getLatestArticles();
      final filteredArticles = await _getFilteredArticles(
        limit: kDefaultPageSize,
        offset: 0,
      );

      if (allCached.isNotEmpty) {
        final autoRefresh = await ref
            .read(appPreferencesProvider)
            .getAutoRefreshOnOpen();
        final shouldSync = !_hasTriggeredStartupSync && autoRefresh;

        // CASO B / C: Hay datos en SQLite -> mostrarlos inmediatamente sin esperar red
        state = state.copyWith(
          articles: filteredArticles,
          totalCachedCount: allCached.length,
          isInitialLoading: false,
          isSyncing: shouldSync,
          hasMore: filteredArticles.length >= kDefaultPageSize,
          isLoadingMore: false,
          clearInitialError: true,
        );

        if (shouldSync) {
          _hasTriggeredStartupSync = true;
          unawaited(_syncWithAbi(hasLocalCache: true));
        } else {
          _hasTriggeredStartupSync = true;
        }
      } else {
        // CASO A / D: Primera instalación (SQLite vacío) -> sincronizar mostrando loading inicial
        state = state.copyWith(
          articles: const <Article>[],
          totalCachedCount: 0,
          isInitialLoading: true,
          isSyncing: true,
          hasMore: false,
          isLoadingMore: false,
          clearInitialError: true,
        );
        _hasTriggeredStartupSync = true;
        await _syncWithAbi(hasLocalCache: false);
      }
    } catch (e) {
      state = state.copyWith(
        isInitialLoading: false,
        isSyncing: false,
        initialErrorMessage: _readableErrorMessage(e),
      );
    }
  }

  /// Carga el siguiente lote de artículos desde SQLite (paginación de 50 en 50).
  Future<void> loadNextPage() async {
    if (state.isLoadingMore ||
        !state.hasMore ||
        state.isInitialLoading ||
        state.isSyncing) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);
    try {
      final nextBatch = await _getFilteredArticles(
        limit: kDefaultPageSize,
        offset: state.articles.length,
      );

      final existingIds = state.articles.map((a) => a.id).toSet();
      final freshArticles =
          nextBatch.where((a) => !existingIds.contains(a.id)).toList();

      state = state.copyWith(
        articles: <Article>[...state.articles, ...freshArticles],
        hasMore: nextBatch.length >= kDefaultPageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Cambia la categoría activa filtrando exclusivamente sobre SQLite,
  /// sin realizar ninguna petición HTTP adicional.
  Future<void> selectCategory(String category) async {
    ref.read(selectedCategoryProvider.notifier).select(category);
    await reloadFromSqlite();
  }

  /// Cambia la fuente activa filtrando sobre SQLite de manera inmediata.
  Future<void> selectSource(String? sourceId) async {
    ref.read(selectedSourceIdProvider.notifier).select(sourceId);
    await reloadFromSqlite();
  }

  /// Sincronización manual mediante Pull-to-Refresh o botón Reintentar.
  /// Devuelve [SyncResult] cuando la sincronización con ABI tuvo éxito.
  Future<SyncResult?> refresh() async {
    final hasCache = state.hasAnyCachedArticles || state.articles.isNotEmpty;
    state = state.copyWith(
      isInitialLoading: !hasCache,
      isSyncing: true,
      clearInitialError: true,
      clearSyncNotice: true,
    );
    return _syncWithAbi(hasLocalCache: hasCache);
  }

  /// Vacía las noticias de SQLite, marca el flag `cacheClearedPendingBaseline`
  /// para evitar que la siguiente sincronización background lance 10
  /// notificaciones masivas, y limpia inmediatamente la pantalla.
  Future<int> clearLocalCache({bool keepFavorites = false}) async {
    await ref.read(appPreferencesProvider).setCacheClearedPendingBaseline(true);
    await ref.read(appPreferencesProvider).clearSeededSources();
    final removed = await _repository.clearCache(keepFavorites: keepFavorites);
    final remaining = await _repository.getLatestArticles();
    final filteredArticles = await _getFilteredArticles(
      limit: kDefaultPageSize,
      offset: 0,
    );

    state = state.copyWith(
      articles: filteredArticles,
      totalCachedCount: remaining.length,
      isInitialLoading: false,
      isSyncing: false,
      hasMore: filteredArticles.length >= kDefaultPageSize,
      isLoadingMore: false,
      clearInitialError: true,
      clearSyncNotice: true,
    );

    ref.invalidate(favoritesProvider);
    ref.invalidate(searchResultsProvider);
    return removed;
  }

  /// Recarga la lista actual desde SQLite sin consultar la red.
  Future<void> reloadFromSqlite() async {
    final allCached = await _repository.getLatestArticles();
    final filteredArticles = await _getFilteredArticles(
      limit: kDefaultPageSize,
      offset: 0,
    );

    state = state.copyWith(
      articles: filteredArticles,
      totalCachedCount: allCached.length,
      isInitialLoading: false,
      hasMore: filteredArticles.length >= kDefaultPageSize,
      isLoadingMore: false,
    );
    ref.invalidate(favoritesProvider);
    ref.invalidate(searchResultsProvider);
  }

  /// Marca un artículo como leído en SQLite y actualiza el estado local.
  Future<void> markAsRead(String articleId) async {
    await _repository.markAsRead(articleId);
    await reloadFromSqlite();
    ref.invalidate(articleDetailProvider(articleId));
  }

  /// Alterna el estado de favorito de un artículo en SQLite y sincroniza todas las vistas.
  Future<void> toggleFavorite(String articleId) async {
    await _repository.toggleFavorite(articleId);
    await reloadFromSqlite();
    ref.invalidate(articleDetailProvider(articleId));
  }

  void dismissSyncNotice() {
    state = state.copyWith(clearSyncNotice: true);
  }

  Future<SyncResult?> _syncWithAbi({required bool hasLocalCache}) async {
    try {
      final syncResult = await _repository.syncLatestArticles();
      if (syncResult.fetched > 0) {
        await ref
            .read(appPreferencesProvider)
            .setCacheClearedPendingBaseline(false);
      }

      final allCached = await _repository.getLatestArticles();
      final filteredArticles = await _getFilteredArticles(
        limit: kDefaultPageSize,
        offset: 0,
      );

      state = state.copyWith(
        articles: filteredArticles,
        totalCachedCount: allCached.length,
        isInitialLoading: false,
        isSyncing: false,
        hasMore: filteredArticles.length >= kDefaultPageSize,
        isLoadingMore: false,
        clearInitialError: true,
        clearSyncNotice: true,
        lastSyncedAt: syncResult.syncedAt,
      );

      ref.invalidate(favoritesProvider);
      ref.invalidate(searchResultsProvider);
      return syncResult;
    } catch (e) {
      final allCached = await _repository.getLatestArticles();
      final filteredArticles = await _getFilteredArticles(
        limit: kDefaultPageSize,
        offset: 0,
      );

      if (allCached.isNotEmpty || hasLocalCache) {
        // CASO C / E: Falla ABI pero SQLite tiene datos -> mantener caché visible + aviso discreto
        state = state.copyWith(
          articles: filteredArticles,
          totalCachedCount: allCached.length,
          isInitialLoading: false,
          isSyncing: false,
          hasMore: filteredArticles.length >= kDefaultPageSize,
          isLoadingMore: false,
          clearInitialError: true,
          syncNoticeMessage:
              'Sin conexión con los medios · Mostrando noticias almacenadas en el dispositivo.',
        );
      } else {
        // CASO D: Primera instalación sin Internet y SQLite vacío -> mostrar error amigable con Reintentar
        state = state.copyWith(
          articles: const <Article>[],
          totalCachedCount: 0,
          isInitialLoading: false,
          isSyncing: false,
          initialErrorMessage: _readableErrorMessage(e),
        );
      }
      return null;
    }
  }

  static String _readableErrorMessage(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return 'No se pudo conectar con las fuentes de noticias. '
        'Verifica tu conexión a Internet e inténtalo nuevamente.';
  }
}

final newsFeedProvider = NotifierProvider<NewsFeedNotifier, NewsFeedState>(
  NewsFeedNotifier.new,
);

/// Provider para obtener el detalle actualizado de un artículo por su ID desde SQLite.
final articleDetailProvider = FutureProvider.autoDispose
    .family<Article?, String>((ref, articleId) async {
      final repository = ref.watch(newsRepositoryProvider);
      return repository.getArticleById(articleId);
    });
