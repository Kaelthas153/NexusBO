import 'package:sqflite/sqflite.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/services/database/app_database.dart';
import 'package:nexusbo/services/database/tables/articles_table.dart';

/// Contrato de la fuente de datos local para noticias en SQLite.
abstract interface class NewsLocalDataSource {
  Future<List<ArticleModel>> getLatestArticles({int limit = 100});

  Future<List<ArticleModel>> getArticlesByCategory(
    String category, {
    int limit = 100,
  });

  /// Consulta genérica de artículos con filtrado combinado opcional por
  /// [category] y [sourceId], ordenados cronológicamente por `published_at DESC`.
  Future<List<ArticleModel>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  });

  /// Consulta artículos para reportes de monitoreo dentro de un rango horario
  /// [startUtc] inclusivo y [endUtc] exclusivo, filtrados por [sourceIds]
  /// y ordenados cronológicamente por `published_at ASC`.
  Future<List<ArticleModel>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  });

  Future<List<ArticleModel>> searchArticles(String query, {int limit = 100});

  Future<List<ArticleModel>> getFavorites();

  Future<ArticleModel?> getArticleById(String id);

  Future<void> markAsRead(String id);

  Future<void> toggleFavorite(String id);

  /// Inserta artículos nuevos y actualiza los existentes mediante
  /// `INSERT ... ON CONFLICT(id) DO UPDATE`, preservando siempre
  /// `is_favorite`, `favorited_at` e `is_read`.
  ///
  /// Devuelve únicamente los [ArticleModel] que NO existían en la base de datos
  /// antes de esta operación.
  Future<List<ArticleModel>> upsertArticles(List<ArticleModel> articles);

  /// Elimina artículos cuya antigüedad supere [retentionPeriod] (por defecto
  /// 30 días), respetando siempre aquellos con `is_favorite = 1`.
  ///
  /// Devuelve la cantidad de filas eliminadas.
  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  });

  /// Elimina los artículos almacenados localmente. Si [keepFavorites] es `true`,
  /// conserva los artículos marcados con `is_favorite = 1`.
  Future<int> clearArticles({bool keepFavorites = false});
}

/// Implementación SQLite de [NewsLocalDataSource].
class SqliteNewsLocalDataSource implements NewsLocalDataSource {
  SqliteNewsLocalDataSource({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  @override
  Future<List<ArticleModel>> getLatestArticles({int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      ArticlesTable.tableName,
      orderBy:
          '${ArticlesTable.colPublishedAt} DESC, ${ArticlesTable.colId} DESC',
      limit: (limit != null && limit > 0) ? limit : null,
    );
    return rows.map(ArticleModel.fromSqliteMap).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticlesByCategory(
    String category, {
    int? limit,
  }) async {
    final normalized = category.trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'todas') {
      return getLatestArticles(limit: limit);
    }

    final canonical = CategoryMapper.toCanonical(normalized);
    final isCanonical = normalized.toLowerCase() == canonical;

    final db = await _db;
    // Consulta primaria: mantiene la cláusula SQL canónica esperada por SQLite y mocks
    final rows = await db.query(
      ArticlesTable.tableName,
      where: '${ArticlesTable.colCategory} = ? COLLATE NOCASE',
      whereArgs: <Object?>[isCanonical ? canonical : normalized],
      orderBy:
          '${ArticlesTable.colPublishedAt} DESC, ${ArticlesTable.colId} DESC',
      limit: (limit != null && limit > 0) ? limit : null,
    );

    if (rows.isEmpty && !isCanonical) {
      // Si la búsqueda con la forma visible ('Economía') no devolvió resultados
      // en bases donde se guardó la forma canónica ('economia'), consulta por canónica.
      final canonicalRows = await db.query(
        ArticlesTable.tableName,
        where: '${ArticlesTable.colCategory} = ? COLLATE NOCASE',
        whereArgs: <Object?>[canonical],
        orderBy:
            '${ArticlesTable.colPublishedAt} DESC, ${ArticlesTable.colId} DESC',
        limit: (limit != null && limit > 0) ? limit : null,
      );
      return canonicalRows.map(ArticleModel.fromSqliteMap).toList(growable: false);
    }

    return rows.map(ArticleModel.fromSqliteMap).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticles({
    String? category,
    String? sourceId,
    int? limit,
    int offset = 0,
  }) async {
    final cleanCategory =
        (category == null ||
            category.trim().isEmpty ||
            category.trim().toLowerCase() == 'todas')
        ? null
        : category.trim();
    final cleanSourceId =
        (sourceId == null ||
            sourceId.trim().isEmpty ||
            sourceId.trim().toLowerCase() == 'todas')
        ? null
        : sourceId.trim();

    final effectiveLimit = (limit != null && limit > 0) ? limit : null;

    if (cleanCategory == null && cleanSourceId == null) {
      final db = await _db;
      final rows = await db.query(
        ArticlesTable.tableName,
        orderBy:
            '${ArticlesTable.colPublishedAt} DESC, ${ArticlesTable.colId} DESC',
        limit: effectiveLimit,
        offset: offset > 0 ? offset : null,
      );
      return rows.map(ArticleModel.fromSqliteMap).toList(growable: false);
    }

    if (cleanCategory != null && cleanSourceId == null && offset == 0) {
      return getArticlesByCategory(cleanCategory, limit: effectiveLimit);
    }

    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (cleanCategory != null) {
      final canonical = CategoryMapper.toCanonical(cleanCategory);
      final isCanonical = cleanCategory.toLowerCase() == canonical;
      whereClauses.add('${ArticlesTable.colCategory} = ? COLLATE NOCASE');
      whereArgs.add(isCanonical ? canonical : cleanCategory);
    }

    if (cleanSourceId != null) {
      whereClauses.add('${ArticlesTable.colSourceId} = ?');
      whereArgs.add(cleanSourceId);
    }

    final db = await _db;
    final rows = await db.query(
      ArticlesTable.tableName,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy:
          '${ArticlesTable.colPublishedAt} DESC, ${ArticlesTable.colId} DESC',
      limit: effectiveLimit,
      offset: offset > 0 ? offset : null,
    );

    if (rows.isEmpty && cleanCategory != null) {
      final canonical = CategoryMapper.toCanonical(cleanCategory);
      if (cleanCategory.toLowerCase() != canonical) {
        final fallbackClauses = <String>[
          '${ArticlesTable.colCategory} = ? COLLATE NOCASE',
        ];
        final fallbackArgs = <Object?>[canonical];
        if (cleanSourceId != null) {
          fallbackClauses.add('${ArticlesTable.colSourceId} = ?');
          fallbackArgs.add(cleanSourceId);
        }
        final fallbackRows = await db.query(
          ArticlesTable.tableName,
          where: fallbackClauses.join(' AND '),
          whereArgs: fallbackArgs,
          orderBy:
              '${ArticlesTable.colPublishedAt} DESC, ${ArticlesTable.colId} DESC',
          limit: effectiveLimit,
          offset: offset > 0 ? offset : null,
        );
        return fallbackRows
            .map(ArticleModel.fromSqliteMap)
            .toList(growable: false);
      }
    }

    return rows.map(ArticleModel.fromSqliteMap).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async {
    final cleanIds = sourceIds
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty && s != 'todas')
        .toList(growable: false);

    if (cleanIds.isEmpty) {
      return const <ArticleModel>[];
    }

    final db = await _db;
    final startMs = BoliviaDateFormatter.toSqliteTimestamp(startUtc);
    final endMs = BoliviaDateFormatter.toSqliteTimestamp(endUtc);

    final placeholders = List<String>.filled(cleanIds.length, '?').join(', ');
    final whereClause =
        '${ArticlesTable.colPublishedAt} >= ? AND ${ArticlesTable.colPublishedAt} < ? AND ${ArticlesTable.colSourceId} IN ($placeholders)';
    final whereArgs = <Object?>[
      startMs,
      endMs,
      ...cleanIds,
    ];

    final rows = await db.query(
      ArticlesTable.tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '${ArticlesTable.colPublishedAt} ASC',
    );

    return rows.map(ArticleModel.fromSqliteMap).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> searchArticles(
    String query, {
    int limit = 100,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <ArticleModel>[];
    }

    // Escapar comodines de LIKE (% y _) para que se busquen literalmente
    final escaped = trimmed
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';

    final db = await _db;
    final rows = await db.query(
      ArticlesTable.tableName,
      where: '''
(
  ${ArticlesTable.colTitle} LIKE ? ESCAPE '\\' OR
  ${ArticlesTable.colSummary} LIKE ? ESCAPE '\\' OR
  ${ArticlesTable.colContentPlain} LIKE ? ESCAPE '\\' OR
  ${ArticlesTable.colCategory} LIKE ? ESCAPE '\\'
)
''',
      whereArgs: <Object?>[pattern, pattern, pattern, pattern],
      orderBy:
          '${ArticlesTable.colPublishedAt} DESC, ${ArticlesTable.colId} DESC',
      limit: limit,
    );
    return rows.map(ArticleModel.fromSqliteMap).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getFavorites() async {
    final db = await _db;
    final rows = await db.query(
      ArticlesTable.tableName,
      where: '${ArticlesTable.colIsFavorite} = 1',
      orderBy: '${ArticlesTable.colFavoritedAt} DESC, ${ArticlesTable.colPublishedAt} DESC',
    );
    return rows.map(ArticleModel.fromSqliteMap).toList(growable: false);
  }

  @override
  Future<ArticleModel?> getArticleById(String id) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) return null;

    final db = await _db;
    final rows = await db.query(
      ArticlesTable.tableName,
      where: '${ArticlesTable.colId} = ?',
      whereArgs: <Object?>[trimmedId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ArticleModel.fromSqliteMap(rows.first);
  }

  @override
  Future<void> markAsRead(String id) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) return;

    final db = await _db;
    await db.update(
      ArticlesTable.tableName,
      <String, Object?>{ArticlesTable.colIsRead: 1},
      where: '${ArticlesTable.colId} = ?',
      whereArgs: <Object?>[trimmedId],
    );
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) return;

    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        ArticlesTable.tableName,
        columns: <String>[ArticlesTable.colIsFavorite],
        where: '${ArticlesTable.colId} = ?',
        whereArgs: <Object?>[trimmedId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final currentVal = rows.first[ArticlesTable.colIsFavorite];
      final isCurrentlyFavorite = currentVal == 1 || currentVal == true;

      if (!isCurrentlyFavorite) {
        final nowUtcMs = BoliviaDateFormatter.toSqliteTimestamp(
          DateTime.now().toUtc(),
        );
        await txn.update(
          ArticlesTable.tableName,
          <String, Object?>{
            ArticlesTable.colIsFavorite: 1,
            ArticlesTable.colFavoritedAt: nowUtcMs,
          },
          where: '${ArticlesTable.colId} = ?',
          whereArgs: <Object?>[trimmedId],
        );
      } else {
        await txn.update(
          ArticlesTable.tableName,
          <String, Object?>{
            ArticlesTable.colIsFavorite: 0,
            ArticlesTable.colFavoritedAt: null,
          },
          where: '${ArticlesTable.colId} = ?',
          whereArgs: <Object?>[trimmedId],
        );
      }
    });
  }

  @override
  Future<List<ArticleModel>> upsertArticles(
    List<ArticleModel> articles,
  ) async {
    if (articles.isEmpty) return const <ArticleModel>[];

    final db = await _db;
    return db.transaction<List<ArticleModel>>((txn) async {
      // 1. Deduplicar la lista entrante por ID manteniendo la última ocurrencia
      final uniqueById = <String, ArticleModel>{};
      for (final article in articles) {
        final trimmedId = article.id.trim();
        if (trimmedId.isEmpty) continue;
        uniqueById[trimmedId] = article;
      }
      if (uniqueById.isEmpty) return const <ArticleModel>[];

      final candidateIds = uniqueById.keys.toList(growable: false);
      final placeholders = List<String>.filled(candidateIds.length, '?').join(',');

      // 2. Identificar qué IDs ya existen en la tabla antes del UPSERT
      final existingRows = await txn.rawQuery(
        'SELECT ${ArticlesTable.colId} FROM ${ArticlesTable.tableName} '
        'WHERE ${ArticlesTable.colId} IN ($placeholders)',
        candidateIds,
      );

      final existingIds = existingRows
          .map((row) => row[ArticlesTable.colId] as String?)
          .whereType<String>()
          .toSet();

      final newlyInserted = <ArticleModel>[];
      final batch = txn.batch();

      // 3. Ejecutar INSERT ... ON CONFLICT(id) DO UPDATE para cada artículo
      for (final entry in uniqueById.entries) {
        final model = entry.value;
        if (!existingIds.contains(entry.key)) {
          newlyInserted.add(model);
        }
        batch.rawInsert(
          ArticlesTable.upsertArticleSql,
          model.toUpsertSqlArgs(),
        );
      }

      await batch.commit(noResult: true);
      return newlyInserted;
    });
  }

  @override
  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  }) async {
    // NUEVA POLÍTICA NEXUSBO: Retención textual indefinida.
    // Los artículos almacenados en SQLite se conservan indefinidamente
    // para consulta histórica y búsqueda offline. Solo se depuran si el
    // usuario ejecuta explícitamente "Limpiar caché de noticias".
    return 0;
  }

  @override
  Future<int> clearArticles({bool keepFavorites = false}) async {
    final db = await _db;
    if (keepFavorites) {
      return db.delete(
        ArticlesTable.tableName,
        where: '${ArticlesTable.colIsFavorite} = 0',
      );
    }
    return db.delete(ArticlesTable.tableName);
  }
}
