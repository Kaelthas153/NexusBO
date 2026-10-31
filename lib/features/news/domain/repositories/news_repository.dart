import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/entities/sync_result.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Contrato único del repositorio de noticias consumido por la capa de
/// presentación (Riverpod) y por el orquestador de sincronización background.
///
/// Sigue el principio Offline-First: todas las lecturas provienen de SQLite y
/// la sincronización remota alimenta a SQLite mediante UPSERT seguro.
abstract interface class NewsRepository {
  Future<List<Article>> getLatestArticles({int limit = 100});

  Future<List<Article>> getArticlesByCategory(
    String category, {
    int limit = 100,
  });

  /// Obtiene artículos desde SQLite aplicando filtrado combinado opcional por
  /// [category] y [sourceId].
  Future<List<Article>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  });

  /// Consulta artículos para reportes de monitoreo dentro del rango horario
  /// [startUtc] inclusivo y [endUtc] exclusivo, filtrados por [sourceIds]
  /// y ordenados cronológicamente por `published_at ASC`.
  Future<List<Article>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  });

  Future<List<Article>> searchArticles(String query, {int limit = 100});

  Future<List<Article>> getFavorites();

  Future<Article?> getArticleById(String id);

  Future<void> markAsRead(String id);

  Future<void> toggleFavorite(String id);

  Future<SyncResult> syncLatestArticles();

  /// Sincroniza un subconjunto específico de fuentes (o todas las habilitadas)
  /// e inserta/actualiza incrementalmente los resultados en SQLite.
  Future<SyncResult> syncSelectedSources([List<NewsSource>? sources]);

  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  });

  Future<int> clearCache({bool keepFavorites = false});
}
