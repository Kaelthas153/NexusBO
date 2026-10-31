/// Definición centralizada del esquema SQLite para la tabla `articles`,
/// sus nombres de columna, índices, migraciones y sentencias parametrizadas.
abstract final class ArticlesTable {
  static const String tableName = 'articles';

  // Columnas
  static const String colId = 'id';
  static const String colTitle = 'title';
  static const String colSummary = 'summary';
  static const String colContentPlain = 'content_plain';
  static const String colUrl = 'url';
  static const String colImageUrl = 'image_url';
  static const String colImageUrlsJson = 'image_urls_json';
  static const String colAuthor = 'author';
  static const String colSourceId = 'source_id';
  static const String colSourceName = 'source_name';
  static const String colCategory = 'category';
  static const String colTagsJson = 'tags_json';
  static const String colPublishedAt = 'published_at';
  static const String colFetchedAt = 'fetched_at';
  static const String colIsFavorite = 'is_favorite';
  static const String colFavoritedAt = 'favorited_at';
  static const String colIsRead = 'is_read';

  static const List<String> allColumns = <String>[
    colId,
    colTitle,
    colSummary,
    colContentPlain,
    colUrl,
    colImageUrl,
    colImageUrlsJson,
    colAuthor,
    colSourceId,
    colSourceName,
    colCategory,
    colTagsJson,
    colPublishedAt,
    colFetchedAt,
    colIsFavorite,
    colFavoritedAt,
    colIsRead,
  ];

  /// DDL de creación de la tabla `articles` (versión 2).
  static const String createTableSql = '''
CREATE TABLE $tableName (
  $colId TEXT PRIMARY KEY,
  $colTitle TEXT NOT NULL,
  $colSummary TEXT NOT NULL,
  $colContentPlain TEXT NOT NULL,
  $colUrl TEXT NOT NULL,
  $colImageUrl TEXT,
  $colImageUrlsJson TEXT NOT NULL DEFAULT '[]',
  $colAuthor TEXT NOT NULL,
  $colSourceId TEXT NOT NULL,
  $colSourceName TEXT NOT NULL,
  $colCategory TEXT NOT NULL,
  $colTagsJson TEXT NOT NULL,
  $colPublishedAt INTEGER NOT NULL,
  $colFetchedAt INTEGER NOT NULL,
  $colIsFavorite INTEGER NOT NULL DEFAULT 0,
  $colFavoritedAt INTEGER,
  $colIsRead INTEGER NOT NULL DEFAULT 0
);
''';

  /// Migración no destructiva v1 -> v2:
  /// Agrega la columna `image_urls_json` preservando todos los artículos,
  /// favoritos y estados de lectura existentes.
  static const String alterTableAddImageUrlsJsonSql =
      "ALTER TABLE $tableName ADD COLUMN $colImageUrlsJson TEXT NOT NULL DEFAULT '[]';";

  /// Rellena `image_urls_json` para las filas existentes de v1 que ya tenían
  /// una `image_url` válida.
  static const String backfillImageUrlsJsonFromImageUrlSql = '''
UPDATE $tableName
SET $colImageUrlsJson = '["' || REPLACE($colImageUrl, '"', '') || '"]'
WHERE $colImageUrl IS NOT NULL AND TRIM($colImageUrl) != '';
''';

  /// Índices requeridos para optimizar ordenamiento, filtrado y favoritos.
  static const List<String> createIndexesSql = <String>[
    'CREATE INDEX idx_articles_published_at '
        'ON $tableName ($colPublishedAt DESC);',
    'CREATE INDEX idx_articles_category_published_at '
        'ON $tableName ($colCategory, $colPublishedAt DESC);',
    'CREATE INDEX idx_articles_is_favorite_favorited_at '
        'ON $tableName ($colIsFavorite, $colFavoritedAt DESC);',
    'CREATE INDEX idx_articles_source_id '
        'ON $tableName ($colSourceId);',
  ];

  /// Sentencia UPSERT segura:
  /// Si el artículo ya existe por `id`, actualiza únicamente los 13 campos
  /// provenientes de la fuente (incluyendo `image_url` e `image_urls_json`)
  /// y preserva intactos `is_favorite`, `favorited_at` e `is_read`.
  static const String upsertArticleSql = '''
INSERT INTO $tableName (
  $colId,
  $colTitle,
  $colSummary,
  $colContentPlain,
  $colUrl,
  $colImageUrl,
  $colImageUrlsJson,
  $colAuthor,
  $colSourceId,
  $colSourceName,
  $colCategory,
  $colTagsJson,
  $colPublishedAt,
  $colFetchedAt,
  $colIsFavorite,
  $colFavoritedAt,
  $colIsRead
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT($colId) DO UPDATE SET
  $colTitle = excluded.$colTitle,
  $colSummary = excluded.$colSummary,
  $colContentPlain = excluded.$colContentPlain,
  $colUrl = excluded.$colUrl,
  $colImageUrl = excluded.$colImageUrl,
  $colImageUrlsJson = excluded.$colImageUrlsJson,
  $colAuthor = excluded.$colAuthor,
  $colSourceId = excluded.$colSourceId,
  $colSourceName = excluded.$colSourceName,
  $colCategory = excluded.$colCategory,
  $colTagsJson = excluded.$colTagsJson,
  $colPublishedAt = excluded.$colPublishedAt,
  $colFetchedAt = excluded.$colFetchedAt;
''';
}
