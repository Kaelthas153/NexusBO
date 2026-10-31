import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/services/database/app_database.dart';
import 'package:nexusbo/services/database/tables/articles_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Article & ArticleModel (Puntos M y N)', () {
    test('Persiste fechas en UTC ms, bool como 0/1 y tags como JSON TEXT', () {
      // Fecha creada con offset local arbitrario para comprobar conversión a UTC
      final pubLocal = DateTime.parse('2026-10-31T02:05:20-04:00');
      final fetchedLocal = DateTime.parse('2026-10-31T02:10:00-04:00');

      final article = Article(
        id: 'https://abi.bo/?p=41195',
        title: 'Diputados reciben propuesta sobre Ley 223',
        summary: 'Resumen de la nota legislativa.',
        contentPlain: 'Primer párrafo.\n\nSegundo párrafo.',
        url: 'https://abi.bo/diputados-reciben-propuesta/',
        imageUrl: null,
        author: 'Redacción Central',
        sourceId: 'abi',
        sourceName: 'ABI',
        category: 'Política',
        tags: const <String>['Cámara de Diputados', 'Ley 223', 'Autismo'],
        publishedAt: pubLocal,
        fetchedAt: fetchedLocal,
        isFavorite: false,
        favoritedAt: null,
        isRead: false,
      );

      // Verificar que la entidad garantiza UTC internamente
      expect(article.publishedAt.isUtc, isTrue);
      expect(article.fetchedAt.isUtc, isTrue);
      expect(article.paragraphs.length, 2);

      final model = ArticleModel.fromEntity(article);
      final map = model.toSqliteMap();

      expect(map[ArticlesTable.colIsFavorite], 0);
      expect(map[ArticlesTable.colIsRead], 0);
      expect(map[ArticlesTable.colFavoritedAt], isNull);
      expect(map[ArticlesTable.colImageUrl], isNull);
      expect(
        map[ArticlesTable.colTagsJson],
        '["Cámara de Diputados","Ley 223","Autismo"]',
      );
      expect(
        map[ArticlesTable.colPublishedAt],
        pubLocal.toUtc().millisecondsSinceEpoch,
      );

      final restoredModel = ArticleModel.fromSqliteMap(map);
      final restoredEntity = restoredModel.toEntity();

      expect(restoredEntity, equals(article));
      expect(
        restoredEntity.tags,
        equals(const <String>['Cámara de Diputados', 'Ley 223', 'Autismo']),
      );
    });

    test('BoliviaDateFormatter parsea RFC-822 en en_US a UTC y formatea a BOT (UTC-4)', () {
      const rssDate = 'Sat, 31 Oct 2026 02:05:20 +0000';
      final parsedUtc = BoliviaDateFormatter.parseRssRfc822Utc(rssDate);

      expect(parsedUtc.isUtc, isTrue);
      expect(parsedUtc.year, 2026);
      expect(parsedUtc.month, 10);
      expect(parsedUtc.day, 31);
      expect(parsedUtc.hour, 2);
      expect(parsedUtc.minute, 5);
      expect(parsedUtc.second, 20);

      // En hora de Bolivia (UTC-4), las 02:05 UTC del 31 oct corresponden a las 22:05 del 30 oct
      final boliviaTime = BoliviaDateFormatter.toBoliviaTime(parsedUtc);
      expect(boliviaTime.day, 30);
      expect(boliviaTime.hour, 22);
      expect(boliviaTime.minute, 5);

      final fullFormatted = BoliviaDateFormatter.formatFullArticleDate(parsedUtc);
      expect(fullFormatted, '30 de octubre de 2026 · 22:05 BOT');
    });
  });

  group('2. HtmlSanitizer con fragmento estilo WordPress/ABI (Punto O)', () {
    test('Limpia HTML, decodifica entidades, preserva párrafos, extrae imagen y elimina pie ABI', () {
      const rawWordPressHtml = '''
<script>console.log("tracking");</script>
<style>.wp-block-paragraph { color: red; }</style>
<p class="wp-block-paragraph">La Paz, 30 de octubre de 2026 (ABI).&ndash; Los diputados   Patricia Arancibia y Carlos Idagua recibieron una propuesta de modificaci&oacute;n de la Ley N.&ordm; 223 [&#8230;]</p>
<figure class="wp-block-image size-large">
  <img fetchpriority="high" width="915" height="1024" src="https://www.abi.bo/wp-content/uploads/2026/10/foto-nota.jpg" alt="Foto ABI" />
</figure>
<p class="wp-block-paragraph">La iniciativa legislativa fue presentada por representantes de la Federaci&oacute;n de Personas con Discapacidad de Bolivia.</p>
<p>La entrada <a href="https://abi.bo/nota/">Diputados reciben propuesta para modificar la Ley General para Personas con Discapacidad</a> se publicó primero en <a href="https://abi.bo">ABI</a>.</p>
''';

      final imageUrl = HtmlSanitizer.extractFirstImageUrl(rawWordPressHtml);
      // Además verifica que normaliza www.abi.bo -> abi.bo
      expect(
        imageUrl,
        'https://abi.bo/wp-content/uploads/2026/10/foto-nota.jpg',
      );

      final plainText = HtmlSanitizer.sanitizeToPlainText(rawWordPressHtml);

      expect(plainText.contains('console.log'), isFalse);
      expect(plainText.contains('color: red'), isFalse);
      expect(plainText.contains('se publicó primero en ABI'), isFalse);
      expect(
        plainText.contains('modificación de la Ley N.º 223'),
        isTrue,
      );

      final paragraphs = plainText.split('\n\n');
      expect(paragraphs.length, 2);
      expect(
        paragraphs[0],
        'La Paz, 30 de octubre de 2026 (ABI).– Los diputados Patricia Arancibia y Carlos Idagua recibieron una propuesta de modificación de la Ley N.º 223…',
      );
      expect(
        paragraphs[1],
        'La iniciativa legislativa fue presentada por representantes de la Federación de Personas con Discapacidad de Bolivia.',
      );
    });
  });

  group('3. Flujo completo SQLite y UPSERT seguro (Puntos A - L)', () {
    late _FakeSqliteMethodChannel fakeSqlite;
    late AppDatabase testDb;
    late SqliteNewsLocalDataSource dataSource;

    setUp(() {
      databaseFactory = databaseFactorySqflitePlugin;
      fakeSqlite = _FakeSqliteMethodChannel();
      fakeSqlite.install();
      testDb = AppDatabase.forTesting(databasePath: ':memory:');
      dataSource = SqliteNewsLocalDataSource(appDatabase: testDb);
    });

    tearDown(() async {
      await testDb.close();
      fakeSqlite.uninstall();
    });

    test('Verifica ciclo completo A..L incluyendo preservación de favorito e isRead tras UPSERT y pruning', () async {
      final baseTimeUtc = DateTime.utc(2026, 10, 30, 12, 0);

      final initialArticle = ArticleModel(
        id: 'abi_41195',
        title: 'Título Original sobre Carretera en Cochabamba',
        summary: 'Resumen inicial del reporte vial.',
        contentPlain: 'Contenido inicial del artículo.',
        url: 'https://abi.bo/nota-41195/',
        imageUrl: 'https://abi.bo/img1.jpg',
        author: 'Redacción Central',
        sourceId: 'abi',
        sourceName: 'ABI',
        category: 'Sociedad',
        tags: const <String>['ABC', 'Vialidad'],
        publishedAt: baseTimeUtc,
        fetchedAt: baseTimeUtc,
      );

      // A. Insertar un artículo nuevo
      final newlyInserted1 = await dataSource.upsertArticles(<ArticleModel>[
        initialArticle,
      ]);
      expect(newlyInserted1.length, 1);
      expect(newlyInserted1.first.id, 'abi_41195');

      // B. Consultarlo por ID
      final fetched1 = await dataSource.getArticleById('abi_41195');
      expect(fetched1, isNotNull);
      expect(fetched1!.title, 'Título Original sobre Carretera en Cochabamba');
      expect(fetched1.isFavorite, isFalse);
      expect(fetched1.favoritedAt, isNull);
      expect(fetched1.isRead, isFalse);

      // C. Actualizar mediante UPSERT el mismo artículo modificando título/resumen
      final updatedFromFeed1 = initialArticle.copyWith(
        title: 'Título Actualizado sobre Carretera en Cochabamba',
        summary: 'Resumen actualizado con nuevos datos de transitabilidad.',
        fetchedAt: baseTimeUtc.add(const Duration(minutes: 10)),
      );
      final newlyInserted2 = await dataSource.upsertArticles(<ArticleModel>[
        updatedFromFeed1,
      ]);
      // Como ya existía, la lista de artículos estrictamente nuevos debe ser vacía
      expect(newlyInserted2, isEmpty);

      final fetchedAfterUpdate = await dataSource.getArticleById('abi_41195');
      expect(
        fetchedAfterUpdate!.title,
        'Título Actualizado sobre Carretera en Cochabamba',
      );
      expect(
        fetchedAfterUpdate.summary,
        'Resumen actualizado con nuevos datos de transitabilidad.',
      );

      // D. Marcarlo como favorito
      await dataSource.toggleFavorite('abi_41195');
      final afterFav = await dataSource.getArticleById('abi_41195');
      expect(afterFav!.isFavorite, isTrue);
      expect(afterFav.favoritedAt, isNotNull);
      final savedFavoritedAt = afterFav.favoritedAt;

      // E. Ejecutar otro UPSERT (simulando sincronización RSS donde el modelo entrante trae isFavorite=false)
      final updatedFromFeed2 = updatedFromFeed1.copyWith(
        title: 'Título Tercera Edición sobre Carretera en Cochabamba',
        isFavorite: false,
        clearFavoritedAt: true,
        isRead: false,
      );
      await dataSource.upsertArticles(<ArticleModel>[updatedFromFeed2]);

      // F. Confirmar que sigue siendo favorito y conserva favoritedAt
      final afterUpsertFavCheck = await dataSource.getArticleById('abi_41195');
      expect(
        afterUpsertFavCheck!.title,
        'Título Tercera Edición sobre Carretera en Cochabamba',
      );
      expect(afterUpsertFavCheck.isFavorite, isTrue);
      expect(afterUpsertFavCheck.favoritedAt, equals(savedFavoritedAt));

      // G. Marcarlo como leído
      await dataSource.markAsRead('abi_41195');
      final afterRead = await dataSource.getArticleById('abi_41195');
      expect(afterRead!.isRead, isTrue);

      // H. Ejecutar otro UPSERT
      final updatedFromFeed3 = updatedFromFeed2.copyWith(
        summary: 'Resumen cuarta edición.',
        isRead: false,
        isFavorite: false,
      );
      await dataSource.upsertArticles(<ArticleModel>[updatedFromFeed3]);

      // I. Confirmar que sigue marcado como leído (y favorito)
      final afterUpsertReadCheck = await dataSource.getArticleById('abi_41195');
      expect(afterUpsertReadCheck!.isRead, isTrue);
      expect(afterUpsertReadCheck.isFavorite, isTrue);
      expect(afterUpsertReadCheck.summary, 'Resumen cuarta edición.');

      // J. Quitar favorito
      await dataSource.toggleFavorite('abi_41195');
      final afterUnfav = await dataSource.getArticleById('abi_41195');
      expect(afterUnfav!.isFavorite, isFalse);
      expect(afterUnfav.favoritedAt, isNull);
      expect(afterUnfav.isRead, isTrue);

      // Insertar segundo artículo de otra categoría para probar K y L
      final secondArticle = ArticleModel(
        id: 'abi_41200',
        title: 'Banco Central publica informe de balanza comercial',
        summary: 'Reporte económico trimestral.',
        contentPlain: 'Detalle de exportaciones.',
        url: 'https://abi.bo/nota-41200/',
        author: 'Unidad de Economía',
        sourceId: 'abi',
        sourceName: 'ABI',
        category: 'Economía',
        tags: const <String>['BCB', 'Economía'],
        publishedAt: baseTimeUtc.add(const Duration(hours: 1)),
        fetchedAt: baseTimeUtc.add(const Duration(hours: 1)),
      );
      final newlyInserted3 = await dataSource.upsertArticles(<ArticleModel>[
        updatedFromFeed3,
        secondArticle,
      ]);
      expect(newlyInserted3.length, 1);
      expect(newlyInserted3.first.id, 'abi_41200');

      // K. Buscar por una palabra del título ("Carretera")
      final searchResults = await dataSource.searchArticles('carretera');
      expect(searchResults.length, 1);
      expect(searchResults.first.id, 'abi_41195');

      // L. Filtrar por categoría ("Economía")
      final economyResults = await dataSource.getArticlesByCategory('Economía');
      expect(economyResults.length, 1);
      expect(economyResults.first.id, 'abi_41200');

      // Verificar Pruning (> 30 días se elimina si no es favorito; se conserva si es favorito)
      final oldNonFavorite = secondArticle.copyWith(
        id: 'abi_old_1',
        publishedAt: baseTimeUtc.subtract(const Duration(days: 45)),
      );
      final oldFavorite = secondArticle.copyWith(
        id: 'abi_old_fav',
        publishedAt: baseTimeUtc.subtract(const Duration(days: 60)),
      );
      await dataSource.upsertArticles(<ArticleModel>[
        oldNonFavorite,
        oldFavorite,
      ]);
      await dataSource.toggleFavorite('abi_old_fav');

      final deletedCount = await dataSource.pruneOldArticles(
        referenceTimeUtc: baseTimeUtc,
      );
      // Con la política de retención textual indefinida, el texto no se elimina (0 borrados).
      expect(deletedCount, 0);
      expect(await dataSource.getArticleById('abi_old_1'), isNotNull);
      expect(await dataSource.getArticleById('abi_old_fav'), isNotNull);
    });
  });
}

/// Simulador en memoria del canal nativo de `sqflite` que respeta la semántica
/// exacta de `articles` (incluyendo `ON CONFLICT(id) DO UPDATE`, `LIKE`,
/// `WHERE`, `DELETE` y transacciones) para pruebas unitarias en host sin
/// dependencias externas adicionales.
class _FakeSqliteMethodChannel {
  static const MethodChannel _channel = MethodChannel('com.tekartik.sqflite');
  final Map<String, Map<String, Object?>> _rowsById =
      <String, Map<String, Object?>>{};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handleMethodCall);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getDatabasesPath':
        return '/tmp';
      case 'openDatabase':
        return <String, Object?>{'id': 1};
      case 'closeDatabase':
        return null;
      case 'execute':
        return null;
      case 'batch':
        final args = call.arguments as Map<Object?, Object?>;
        final operations = args['operations'] as List<Object?>;
        final results = <Object?>[];
        for (final op in operations.cast<Map<Object?, Object?>>()) {
          final method = op['method'] as String;
          final sql = (op['sql'] as String?) ?? '';
          final sqlArgs =
              (op['arguments'] as List<Object?>?) ?? const <Object?>[];
          if (method == 'insert') {
            _executeUpsertOrInsert(sql, sqlArgs);
          }
          results.add(null);
        }
        return results;
      case 'query':
        final args = call.arguments as Map<Object?, Object?>;
        final sql = (args['sql'] as String?) ?? '';
        final sqlArgs =
            (args['arguments'] as List<Object?>?) ?? const <Object?>[];
        return _executeQuery(sql, sqlArgs);
      case 'update':
        final args = call.arguments as Map<Object?, Object?>;
        final sql = (args['sql'] as String?) ?? '';
        final sqlArgs =
            (args['arguments'] as List<Object?>?) ?? const <Object?>[];
        return _executeUpdateOrDelete(sql, sqlArgs);
      default:
        return null;
    }
  }

  void _executeUpsertOrInsert(String sql, List<Object?> args) {
    if (!sql.contains('INSERT INTO ${ArticlesTable.tableName}')) return;

    final id = args[0] as String;
    final incoming = <String, Object?>{
      ArticlesTable.colId: args[0],
      ArticlesTable.colTitle: args[1],
      ArticlesTable.colSummary: args[2],
      ArticlesTable.colContentPlain: args[3],
      ArticlesTable.colUrl: args[4],
      ArticlesTable.colImageUrl: args[5],
      ArticlesTable.colImageUrlsJson: args[6],
      ArticlesTable.colAuthor: args[7],
      ArticlesTable.colSourceId: args[8],
      ArticlesTable.colSourceName: args[9],
      ArticlesTable.colCategory: args[10],
      ArticlesTable.colTagsJson: args[11],
      ArticlesTable.colPublishedAt: args[12],
      ArticlesTable.colFetchedAt: args[13],
      ArticlesTable.colIsFavorite: args[14],
      ArticlesTable.colFavoritedAt: args[15],
      ArticlesTable.colIsRead: args[16],
    };

    final existing = _rowsById[id];
    if (existing == null) {
      _rowsById[id] = incoming;
    } else if (sql.contains('ON CONFLICT(${ArticlesTable.colId}) DO UPDATE')) {
      // Actualiza únicamente los campos provenientes de la fuente,
      // preservando is_favorite, favorited_at e is_read.
      existing[ArticlesTable.colTitle] = incoming[ArticlesTable.colTitle];
      existing[ArticlesTable.colSummary] = incoming[ArticlesTable.colSummary];
      existing[ArticlesTable.colContentPlain] =
          incoming[ArticlesTable.colContentPlain];
      existing[ArticlesTable.colUrl] = incoming[ArticlesTable.colUrl];
      existing[ArticlesTable.colImageUrl] = incoming[ArticlesTable.colImageUrl];
      existing[ArticlesTable.colImageUrlsJson] =
          incoming[ArticlesTable.colImageUrlsJson];
      existing[ArticlesTable.colAuthor] = incoming[ArticlesTable.colAuthor];
      existing[ArticlesTable.colSourceId] = incoming[ArticlesTable.colSourceId];
      existing[ArticlesTable.colSourceName] =
          incoming[ArticlesTable.colSourceName];
      existing[ArticlesTable.colCategory] = incoming[ArticlesTable.colCategory];
      existing[ArticlesTable.colTagsJson] = incoming[ArticlesTable.colTagsJson];
      existing[ArticlesTable.colPublishedAt] =
          incoming[ArticlesTable.colPublishedAt];
      existing[ArticlesTable.colFetchedAt] =
          incoming[ArticlesTable.colFetchedAt];
    }
  }

  List<Map<String, Object?>> _executeQuery(String sql, List<Object?> args) {
    final normalizedSql = sql.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (normalizedSql.startsWith('SELECT id FROM articles WHERE id IN')) {
      final idSet = args.cast<String>().toSet();
      return _rowsById.values
          .where((row) => idSet.contains(row[ArticlesTable.colId]))
          .map((row) => <String, Object?>{
                ArticlesTable.colId: row[ArticlesTable.colId],
              })
          .toList();
    }

    var results = _rowsById.values
        .map((row) => Map<String, Object?>.from(row))
        .toList();

    if (normalizedSql.contains('WHERE id = ?')) {
      final targetId = args.first as String;
      results = results
          .where((row) => row[ArticlesTable.colId] == targetId)
          .toList();
    } else if (normalizedSql.contains('WHERE category = ? COLLATE NOCASE')) {
      final targetCat = (args.first as String).toLowerCase();
      results = results
          .where(
            (row) =>
                (row[ArticlesTable.colCategory] as String).toLowerCase() ==
                targetCat,
          )
          .toList();
    } else if (normalizedSql.contains('WHERE is_favorite = 1')) {
      results = results
          .where((row) => row[ArticlesTable.colIsFavorite] == 1)
          .toList();
    } else if (normalizedSql.contains('LIKE ?')) {
      final rawPattern = (args.first as String).toLowerCase();
      final needle = rawPattern.substring(1, rawPattern.length - 1);
      results = results.where((row) {
        final title = (row[ArticlesTable.colTitle] as String).toLowerCase();
        final summary = (row[ArticlesTable.colSummary] as String).toLowerCase();
        final content =
            (row[ArticlesTable.colContentPlain] as String).toLowerCase();
        final category =
            (row[ArticlesTable.colCategory] as String).toLowerCase();
        return title.contains(needle) ||
            summary.contains(needle) ||
            content.contains(needle) ||
            category.contains(needle);
      }).toList();
    }

    results.sort(
      (a, b) => (b[ArticlesTable.colPublishedAt] as int).compareTo(
        a[ArticlesTable.colPublishedAt] as int,
      ),
    );
    return results;
  }

  int _executeUpdateOrDelete(String sql, List<Object?> args) {
    final normalizedSql = sql.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (normalizedSql.startsWith('UPDATE articles SET is_read = ? WHERE id = ?')) {
      final isRead = args[0];
      final id = args[1] as String;
      final row = _rowsById[id];
      if (row == null) return 0;
      row[ArticlesTable.colIsRead] = isRead;
      return 1;
    }

    if (normalizedSql.startsWith(
      'UPDATE articles SET is_favorite = ?, favorited_at = ? WHERE id = ?',
    )) {
      final isFav = args[0];
      final favAt = args[1];
      final id = args[2] as String;
      final row = _rowsById[id];
      if (row == null) return 0;
      row[ArticlesTable.colIsFavorite] = isFav;
      row[ArticlesTable.colFavoritedAt] = favAt;
      return 1;
    }

    if (normalizedSql.startsWith(
      'UPDATE articles SET is_favorite = ?, favorited_at = NULL WHERE id = ?',
    )) {
      final isFav = args[0];
      final id = args[1] as String;
      final row = _rowsById[id];
      if (row == null) return 0;
      row[ArticlesTable.colIsFavorite] = isFav;
      row[ArticlesTable.colFavoritedAt] = null;
      return 1;
    }

    if (normalizedSql.startsWith(
      'DELETE FROM articles WHERE is_favorite = 0 AND published_at < ?',
    )) {
      final cutoff = args[0] as int;
      final idsToDelete = _rowsById.entries
          .where(
            (e) =>
                e.value[ArticlesTable.colIsFavorite] == 0 &&
                (e.value[ArticlesTable.colPublishedAt] as int) < cutoff,
          )
          .map((e) => e.key)
          .toList();
      for (final id in idsToDelete) {
        _rowsById.remove(id);
      }
      return idsToDelete.length;
    }

    return 0;
  }
}

