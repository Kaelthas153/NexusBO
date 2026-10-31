import 'package:nexusbo/features/news/domain/entities/article.dart';

/// Resultado resumido de una operación de sincronización remota hacia SQLite.
class SyncResult {
  SyncResult({
    required this.fetched,
    required this.inserted,
    required DateTime syncedAt,
    List<Article> newArticles = const <Article>[],
    this.warning,
  }) : syncedAt = syncedAt.toUtc(),
       newArticles = List<Article>.unmodifiable(newArticles);

  /// Cantidad de artículos válidos obtenidos del feed remoto.
  final int fetched;

  /// Cantidad de artículos que eran completamente nuevos antes del UPSERT.
  final int inserted;

  /// Instante UTC en el que concluyó la sincronización.
  final DateTime syncedAt;

  /// Artículos que NO existían en SQLite antes del UPSERT de esta sincronización.
  final List<Article> newArticles;

  /// Mensaje de advertencia opcional cuando ocurre una anomalía no fatal
  /// (por ejemplo, feed remoto vacío).
  final String? warning;

  @override
  String toString() {
    return 'SyncResult(fetched: $fetched, inserted: $inserted, '
        'syncedAt: ${syncedAt.toIso8601String()}, warning: $warning)';
  }
}
