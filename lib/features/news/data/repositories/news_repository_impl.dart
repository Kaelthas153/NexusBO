import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/datasources/news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/entities/sync_result.dart';
import 'package:nexusbo/features/news/domain/repositories/news_repository.dart';
import 'package:nexusbo/features/news/domain/sources/multi_source_sync_engine.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Implementación Offline-First de [NewsRepository].
///
/// Garantiza que SQLite sea la única fuente de verdad (Single Source of Truth)
/// para la interfaz de usuario y que ningún fallo de red ni anomalía de una fuente
/// elimine o sobrescriba destructivamente las noticias almacenadas localmente.
class NewsRepositoryImpl implements NewsRepository {
  NewsRepositoryImpl({
    required NewsLocalDataSource localDataSource,
    NewsRemoteDataSource? remoteDataSource,
    MultiSourceSyncEngine? syncEngine,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _syncEngine = syncEngine;

  final NewsLocalDataSource _localDataSource;
  final NewsRemoteDataSource? _remoteDataSource;
  final MultiSourceSyncEngine? _syncEngine;

  @override
  Future<List<Article>> getLatestArticles({int limit = 100}) async {
    try {
      final models = await _localDataSource.getLatestArticles(limit: limit);
      return models.map((m) => m.toEntity()).toList(growable: false);
    } catch (e) {
      throw DatabaseException(
        'Error al leer las noticias almacenadas localmente.',
        cause: e,
      );
    }
  }

  @override
  Future<List<Article>> getArticlesByCategory(
    String category, {
    int limit = 100,
  }) async {
    try {
      final models = await _localDataSource.getArticlesByCategory(
        category,
        limit: limit,
      );
      return models.map((m) => m.toEntity()).toList(growable: false);
    } catch (e) {
      throw DatabaseException(
        'Error al filtrar noticias por la categoría "$category".',
        cause: e,
      );
    }
  }

  @override
  Future<List<Article>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final models = await _localDataSource.getArticles(
        category: category,
        sourceId: sourceId,
        limit: limit,
        offset: offset,
      );
      return models.map((m) => m.toEntity()).toList(growable: false);
    } catch (e) {
      throw DatabaseException(
        'Error al filtrar noticias (categoría: $category, fuente: $sourceId).',
        cause: e,
      );
    }
  }

  @override
  Future<List<Article>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async {
    try {
      final models = await _localDataSource.getArticlesForReport(
        startUtc: startUtc,
        endUtc: endUtc,
        sourceIds: sourceIds,
      );
      return models.map((m) => m.toEntity()).toList(growable: false);
    } catch (e) {
      throw DatabaseException(
        'Error al obtener artículos para el reporte de monitoreo.',
        cause: e,
      );
    }
  }

  @override
  Future<List<Article>> searchArticles(
    String query, {
    int limit = 100,
  }) async {
    try {
      final models = await _localDataSource.searchArticles(query, limit: limit);
      return models.map((m) => m.toEntity()).toList(growable: false);
    } catch (e) {
      throw DatabaseException(
        'Error al realizar la búsqueda local de noticias.',
        cause: e,
      );
    }
  }

  @override
  Future<List<Article>> getFavorites() async {
    try {
      final models = await _localDataSource.getFavorites();
      return models.map((m) => m.toEntity()).toList(growable: false);
    } catch (e) {
      throw DatabaseException(
        'Error al cargar las noticias guardadas.',
        cause: e,
      );
    }
  }

  @override
  Future<Article?> getArticleById(String id) async {
    try {
      final model = await _localDataSource.getArticleById(id);
      return model?.toEntity();
    } catch (e) {
      throw DatabaseException(
        'Error al consultar el detalle de la noticia.',
        cause: e,
      );
    }
  }

  @override
  Future<void> markAsRead(String id) async {
    try {
      await _localDataSource.markAsRead(id);
    } catch (e) {
      throw DatabaseException(
        'Error al actualizar el estado de lectura.',
        cause: e,
      );
    }
  }

  @override
  Future<void> toggleFavorite(String id) async {
    try {
      await _localDataSource.toggleFavorite(id);
    } catch (e) {
      throw DatabaseException(
        'Error al actualizar el estado de favorito.',
        cause: e,
      );
    }
  }

  @override
  Future<SyncResult> syncLatestArticles() async {
    return syncSelectedSources();
  }

  @override
  Future<SyncResult> syncSelectedSources([List<NewsSource>? sources]) async {
    final nowUtc = DateTime.now().toUtc();
    final List<ArticleModel> remoteArticles;
    String? warningMessage;

    if (_syncEngine != null) {
      final sourceResults =
          await _syncEngine.fetchAllSources(targetSources: sources);
      final failedSources = sourceResults.where((r) => r.hasError).toList();
      final successSources = sourceResults.where((r) => r.isSuccess).toList();

      if (failedSources.isNotEmpty) {
        final names = failedSources.map((r) => r.sourceName).join(', ');
        warningMessage = 'Aviso: No fue posible sincronizar con $names.';
      }

      remoteArticles = sourceResults
          .where((r) => r.isSuccess)
          .expand((r) => r.articles)
          .toList();

      // Si todas las fuentes fallaron y no obtuvimos ningún artículo, relanzar la
      // excepción si fue por error de red para permitir reintentos (retry en WorkManager).
      if (successSources.isEmpty && failedSources.isNotEmpty) {
        final firstError = failedSources.first.error;
        if (firstError is AppException) {
          throw firstError;
        } else if (firstError != null) {
          throw NetworkException(
            'Error al sincronizar con las fuentes de noticias.',
            cause: firstError,
          );
        }
      }
    } else if (_remoteDataSource != null) {
      remoteArticles = await _remoteDataSource.fetchLatestArticles();
    } else {
      remoteArticles = const <ArticleModel>[];
    }

    // Si las fuentes remotas devuelven 0 artículos por una anomalía temporal,
    // preservamos intacta la base SQLite sin vaciar ni alterar nada.
    if (remoteArticles.isEmpty) {
      return SyncResult(
        fetched: 0,
        inserted: 0,
        syncedAt: nowUtc,
        newArticles: const <Article>[],
        warning: warningMessage ??
            'Las fuentes no devolvieron artículos en esta consulta.',
      );
    }

    try {
      final newlyInserted = await _localDataSource.upsertArticles(
        remoteArticles,
      );
      final newEntities = newlyInserted
          .map((m) => m.toEntity())
          .toList(growable: false);
      return SyncResult(
        fetched: remoteArticles.length,
        inserted: newEntities.length,
        syncedAt: nowUtc,
        newArticles: newEntities,
        warning: warningMessage,
      );
    } catch (e) {
      throw DatabaseException(
        'Error al guardar en SQLite las noticias recibidas.',
        cause: e,
      );
    }
  }

  @override
  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  }) async {
    try {
      return await _localDataSource.pruneOldArticles(
        retentionPeriod: retentionPeriod,
        referenceTimeUtc: referenceTimeUtc,
      );
    } catch (e) {
      throw DatabaseException(
        'Error al depurar noticias antiguas de SQLite.',
        cause: e,
      );
    }
  }

  @override
  Future<int> clearCache({bool keepFavorites = false}) async {
    try {
      return await _localDataSource.clearArticles(keepFavorites: keepFavorites);
    } catch (e) {
      throw DatabaseException(
        'Error al limpiar la caché local de noticias.',
        cause: e,
      );
    }
  }
}
