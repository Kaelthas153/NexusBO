import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/datasources/news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/datasources/rss_news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/data/repositories/news_repository_impl.dart';
import 'package:nexusbo/services/database/app_database.dart';
import 'package:nexusbo/services/database/tables/articles_table.dart';

/// Fixture RSS 2.0 local basada fielmente en la estructura real de
/// `https://abi.bo/feed/` (WordPress 7.0.2).
const String kAbiRssFixtureXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:content="http://purl.org/rss/1.0/modules/content/"
  xmlns:wfw="http://wellformedweb.org/CommentAPI/"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:atom="http://www.w3.org/2005/Atom"
  xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
  xmlns:slash="http://purl.org/rss/1.0/modules/slash/"
  xmlns:media="http://search.yahoo.com/mrss/">
<channel>
  <title>ABI</title>
  <link>https://abi.bo/</link>
  <description>Agencia Boliviana de Información – Noticias oficiales del Estado Plurinacional de Bolivia.</description>
  <language>es</language>

  <!-- ITEM 1: Tiene <img> dentro de content:encoded + imagen principal og:image en su página -->
  <item>
    <title>ABC levanta varios cortes y restricciones en carreteras del pa&#237;s ante un fin de semana largo</title>
    <link>https://www.abi.bo/abc-levanta-varios-cortes-y-restricciones/</link>
    <dc:creator><![CDATA[Redacción Central]]></dc:creator>
    <pubDate>Sat, 31 Oct 2026 01:53:28 +0000</pubDate>
    <category><![CDATA[Sociedad]]></category>
    <category><![CDATA[ABC]]></category>
    <category><![CDATA[carretera]]></category>
    <guid isPermaLink="false">https://abi.bo/?p=41191</guid>
    <description><![CDATA[<p>La Paz, 30 de octubre de 2026 (ABI).&ndash; La Administradora Boliviana de Carreteras (ABC) inform&oacute; sobre el levantamiento temporal de cortes en el pa&iacute;s [&#8230;]</p>
<p>La entrada <a href="https://abi.bo/abc-levanta-varios-cortes-y-restricciones/">ABC levanta varios cortes</a> se publicó primero en <a href="https://abi.bo">ABI</a>.</p>]]></description>
    <content:encoded><![CDATA[
<p class="wp-block-paragraph">La Paz, 30 de octubre de 2026 (ABI).– La Administradora Boliviana de Carreteras (ABC), en coordinación con el Ministerio de Obras Públicas, informó sobre el levantamiento temporal de varios cortes en la Red Vial Fundamental.</p>
<figure class="wp-block-image size-large"><img fetchpriority="high" width="915" height="1024" src="https://www.abi.bo/wp-content/uploads/2026/10/mapa-carreteras.jpg" alt="Mapa ABC" /></figure>
<p class="wp-block-paragraph">En Santa Cruz, se levantan los cortes en el tramo Bermejo-La Angostura del 31 de octubre al 2 de noviembre.</p>
<p>La entrada <a href="https://abi.bo/abc-levanta-varios-cortes-y-restricciones/">ABC levanta varios cortes y restricciones en carreteras del país ante un fin de semana largo</a> se publicó primero en <a href="https://abi.bo">ABI</a>.</p>
]]></content:encoded>
  </item>

  <!-- ITEM 2: Artículo realmente sin imagen en RSS ni en página -->
  <item>
    <title>Gálvez: el 95% de los recursos salariales del TGN se destina a servicios esenciales</title>
    <link>https://abi.bo/galvez-el-95-de-los-recursos-salariales/</link>
    <dc:creator><![CDATA[]]></dc:creator>
    <pubDate>Sat, 31 Oct 2026 01:31:54 +0000</pubDate>
    <category><![CDATA[Noticias Destacadas]]></category>
    <category><![CDATA[Economia]]></category>
    <category><![CDATA[Tesoro General de la Nación]]></category>
    <category><![CDATA[Economía]]></category>
    <guid isPermaLink="false">https://abi.bo/?p=41179</guid>
    <description><![CDATA[]]></description>
    <content:encoded><![CDATA[
<p class="wp-block-paragraph">La Paz, 30 de octubre de 2026 (ABI).– El vocero presidencial explicó la distribución presupuestaria para salud, educación y seguridad ciudadana.</p>
<p class="wp-block-paragraph">También destacó que el PGE 2027 garantiza las políticas sociales vigentes.</p>
]]></content:encoded>
  </item>

  <!-- ITEM 3: Artículo con <media:content> prioritario y segunda imagen en content:encoded -->
  <item>
    <title>Diputados reciben propuesta para modificar la Ley N.º 223</title>
    <link>https://abi.bo/diputados-ley-223/</link>
    <dc:creator><![CDATA[Unidad Legislativa]]></dc:creator>
    <pubDate>Sat, 31 Oct 2026 02:05:20 +0000</pubDate>
    <category><![CDATA[Política]]></category>
    <category><![CDATA[Cámara de Diputados]]></category>
    <guid isPermaLink="true">https://www.abi.bo/diputados-ley-223/</guid>
    <media:content url="https://www.abi.bo/wp-content/uploads/2026/10/diputados-media.jpg" medium="image" type="image/jpeg" />
    <description><![CDATA[<p>Comisión legislativa analiza propuestas de organizaciones sociales.</p>]]></description>
    <content:encoded><![CDATA[
<p>Comisión legislativa analiza propuestas de organizaciones sociales para fortalecer la Ley N.º 223.</p>
<img src="https://abi.bo/wp-content/uploads/2026/10/otra-imagen-secundaria.jpg" />
]]></content:encoded>
  </item>

  <!-- ITEM 4: Defectuoso (sin título) -> debe ignorarse sin romper los demás -->
  <item>
    <title>   </title>
    <link>https://abi.bo/item-defectuoso/</link>
    <guid isPermaLink="false">https://abi.bo/?p=99999</guid>
  </item>
</channel>
</rss>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Parser RSS de ABI, imágenes destacadas y múltiples imágenes (Puntos A - P)', () {
    late RssNewsRemoteDataSource rssDataSource;
    final fixedFetchedAt = DateTime.utc(2026, 10, 31, 3, 0, 0);

    setUp(() {
      rssDataSource = RssNewsRemoteDataSource(dioClient: DioClient());
    });

    test('Verifica parseo completo A..O, extracción de og:image y múltiples imágenes', () {
      // Simulamos el HTML de la página del Item 1 con su imagen principal og:image / wp-post-image
      final pageHtmlMap = <String, String>{
        'https://abi.bo/abc-levanta-varios-cortes-y-restricciones/': '''
<!DOCTYPE html>
<html>
<head>
  <meta property="og:image" content="https://www.abi.bo/wp-content/uploads/2026/10/portada-abc-camiones.jpg" />
</head>
<body>
  <img class="img-fluid single-featured-image wp-post-image" src="https://abi.bo/wp-content/uploads/2026/10/portada-abc-camiones.jpg" />
</body>
</html>
''',
      };

      final articles = rssDataSource.parseRssXml(
        kAbiRssFixtureXml,
        fetchedAtOverrideUtc: fixedFetchedAt,
        articlePageHtmlByUrl: pageHtmlMap,
      );

      expect(articles.length, 3);

      // -----------------------------------------------------------------------
      // Verificación Item 1: Combina og:image (principal) + <img> de content:encoded
      // -----------------------------------------------------------------------
      final item1 = articles[0];
      expect(
        item1.title,
        'ABC levanta varios cortes y restricciones en carreteras del país ante un fin de semana largo',
      );
      expect(item1.id, 'abi_41191');
      expect(
        item1.url,
        'https://abi.bo/abc-levanta-varios-cortes-y-restricciones/',
      );
      expect(item1.contentPlain.contains('se publicó primero en ABI'), isFalse);
      expect(item1.toEntity().paragraphs.length, 2);
      expect(item1.author, 'Redacción Central');
      expect(item1.publishedAt, DateTime.utc(2026, 10, 31, 1, 53, 28));
      expect(item1.category, 'Sociedad');
      expect(item1.tags, equals(const <String>['ABC', 'carretera']));

      // Imagen principal proviene de og:image de la página del artículo
      expect(
        item1.imageUrl,
        'https://abi.bo/wp-content/uploads/2026/10/portada-abc-camiones.jpg',
      );
      // Y conserva ambas imágenes (la principal de portada + el mapa dentro de content:encoded)
      expect(
        item1.imageUrls,
        equals(const <String>[
          'https://abi.bo/wp-content/uploads/2026/10/portada-abc-camiones.jpg',
          'https://abi.bo/wp-content/uploads/2026/10/mapa-carreteras.jpg',
        ]),
      );
      expect(item1.toEntity().hasMultipleImages, isTrue);

      // -----------------------------------------------------------------------
      // Verificación Item 2: Sin imagen ni en RSS ni en página -> null y []
      // -----------------------------------------------------------------------
      final item2 = articles[1];
      expect(item2.id, 'abi_41179');
      expect(item2.author, 'ABI');
      expect(item2.category, 'Economía');
      expect(item2.imageUrl, isNull);
      expect(item2.imageUrls, isEmpty);

      // -----------------------------------------------------------------------
      // Verificación Item 3: <media:content> prioritario + 2da imagen de content
      // -----------------------------------------------------------------------
      final item3 = articles[2];
      expect(item3.id, 'https://abi.bo/diputados-ley-223/');
      expect(
        item3.imageUrl,
        'https://abi.bo/wp-content/uploads/2026/10/diputados-media.jpg',
      );
      expect(
        item3.imageUrls,
        equals(const <String>[
          'https://abi.bo/wp-content/uploads/2026/10/diputados-media.jpg',
          'https://abi.bo/wp-content/uploads/2026/10/otra-imagen-secundaria.jpg',
        ]),
      );
    });

    test('P. XML completamente inválido lanza ParseException', () {
      expect(
        () => rssDataSource.parseRssXml('<rss><channel><item>XML roto'),
        throwsA(isA<ParseException>()),
      );

      expect(
        () => rssDataSource.parseRssXml('<html><body>No es RSS</body></html>'),
        throwsA(isA<ParseException>()),
      );
    });
  });

  group('2. Persistencia incremental y Offline-First en NewsRepositoryImpl', () {
    late _InMemorySqliteMock sqliteMock;
    late AppDatabase testDb;
    late SqliteNewsLocalDataSource localDataSource;
    late _ControllableRemoteDataSource remoteDataSource;
    late NewsRepositoryImpl repository;

    setUp(() {
      databaseFactory = databaseFactorySqflitePlugin;
      sqliteMock = _InMemorySqliteMock()..install();
      testDb = AppDatabase.forTesting(databasePath: ':memory:');
      localDataSource = SqliteNewsLocalDataSource(appDatabase: testDb);
      remoteDataSource = _ControllableRemoteDataSource();
      repository = NewsRepositoryImpl(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );
    });

    tearDown(() async {
      await testDb.close();
      sqliteMock.uninstall();
    });

    test('Persistencia incremental: 10 iniciales -> +1 nueva = 11 -> +3 nuevas = 14 sin perder anteriores ni favoritos', () async {
      final baseTime = DateTime.utc(2026, 10, 31, 0, 0);

      List<ArticleModel> buildFeedWindow(int startIdx, int count) {
        return List<ArticleModel>.generate(count, (offset) {
          final numId = startIdx + offset;
          return ArticleModel(
            id: 'abi_$numId',
            title: 'Noticia de ABI número $numId',
            summary: 'Resumen de la noticia $numId.',
            contentPlain: 'Cuerpo completo de la noticia $numId.',
            url: 'https://abi.bo/?p=$numId',
            imageUrl: 'https://abi.bo/wp-content/uploads/foto_$numId.jpg',
            imageUrls: <String>[
              'https://abi.bo/wp-content/uploads/foto_$numId.jpg',
              'https://abi.bo/wp-content/uploads/galeria_${numId}_2.jpg',
            ],
            author: 'Redacción Central',
            sourceId: 'abi',
            sourceName: 'ABI',
            category: 'Política',
            tags: const <String>['Bolivia'],
            publishedAt: baseTime.add(Duration(minutes: numId)),
            fetchedAt: baseTime.add(Duration(minutes: numId)),
          );
        });
      }

      // 1. Primera sincronización: 10 noticias (abi_1 .. abi_10)
      remoteDataSource.nextArticles = buildFeedWindow(1, 10);
      final sync1 = await repository.syncLatestArticles();
      expect(sync1.fetched, 10);
      expect(sync1.inserted, 10);

      final storedAfterSync1 = await repository.getLatestArticles();
      expect(storedAfterSync1.length, 10);

      // Marcar la noticia más antigua (abi_1) como favorita y leída
      await repository.toggleFavorite('abi_1');
      await repository.markAsRead('abi_1');

      // 2. ABI publica 1 noticia nueva: el RSS ahora entrega abi_2 .. abi_11 (10 items)
      // abi_1 ya no viene en el RSS, pero debe conservarse en SQLite -> total 11
      remoteDataSource.nextArticles = buildFeedWindow(2, 10);
      final sync2 = await repository.syncLatestArticles();
      expect(sync2.fetched, 10);
      expect(sync2.inserted, 1);

      final storedAfterSync2 = await repository.getLatestArticles();
      expect(storedAfterSync2.length, 11);

      // Confirmar que abi_1 sigue almacenada y conserva favorito e isRead
      final oldestStillPresent = await repository.getArticleById('abi_1');
      expect(oldestStillPresent, isNotNull);
      expect(oldestStillPresent!.isFavorite, isTrue);
      expect(oldestStillPresent.isRead, isTrue);
      expect(oldestStillPresent.imageUrls.length, 2);

      // 3. ABI publica otras 3 noticias nuevas: el RSS entrega abi_5 .. abi_14 (10 items)
      // Deben conservarse abi_1 .. abi_4 y agregarse abi_12, abi_13, abi_14 -> total 14
      remoteDataSource.nextArticles = buildFeedWindow(5, 10);
      final sync3 = await repository.syncLatestArticles();
      expect(sync3.fetched, 10);
      expect(sync3.inserted, 3);

      final storedAfterSync3 = await repository.getLatestArticles();
      expect(storedAfterSync3.length, 14);

      // 4. Si ABI falla posteriormente por red, las 14 noticias siguen intactas
      remoteDataSource.shouldThrowNetworkError = true;
      await expectLater(
        repository.syncLatestArticles(),
        throwsA(isA<NetworkException>()),
      );
      expect((await repository.getLatestArticles()).length, 14);
    });
  });
}

class _ControllableRemoteDataSource implements NewsRemoteDataSource {
  List<ArticleModel> nextArticles = const <ArticleModel>[];
  bool shouldThrowNetworkError = false;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    if (shouldThrowNetworkError) {
      throw const NetworkException('Simulated network failure');
    }
    return nextArticles;
  }
}

class _InMemorySqliteMock {
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
      case 'execute':
        return null;
      case 'batch':
        final args = call.arguments as Map<Object?, Object?>;
        final operations = args['operations'] as List<Object?>;
        for (final op in operations.cast<Map<Object?, Object?>>()) {
          if (op['method'] == 'insert') {
            final sql = (op['sql'] as String?) ?? '';
            final sqlArgs =
                (op['arguments'] as List<Object?>?) ?? const <Object?>[];
            _upsert(sql, sqlArgs);
          }
        }
        return List<Object?>.filled(operations.length, null);
      case 'query':
        final args = call.arguments as Map<Object?, Object?>;
        final sql = (args['sql'] as String?) ?? '';
        final sqlArgs =
            (args['arguments'] as List<Object?>?) ?? const <Object?>[];
        return _query(sql, sqlArgs);
      case 'update':
        final args = call.arguments as Map<Object?, Object?>;
        final sql = (args['sql'] as String?) ?? '';
        final sqlArgs =
            (args['arguments'] as List<Object?>?) ?? const <Object?>[];
        return _update(sql, sqlArgs);
      default:
        return null;
    }
  }

  void _upsert(String sql, List<Object?> args) {
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

  List<Map<String, Object?>> _query(String sql, List<Object?> args) {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.startsWith('SELECT id FROM articles WHERE id IN')) {
      final idSet = args.cast<String>().toSet();
      return _rowsById.values
          .where((r) => idSet.contains(r[ArticlesTable.colId]))
          .map((r) => <String, Object?>{
                ArticlesTable.colId: r[ArticlesTable.colId],
              })
          .toList();
    }

    var list = _rowsById.values
        .map((r) => Map<String, Object?>.from(r))
        .toList();

    if (normalized.contains('WHERE id = ?')) {
      list = list.where((r) => r[ArticlesTable.colId] == args.first).toList();
    } else if (normalized.contains('WHERE is_favorite = 1')) {
      list = list.where((r) => r[ArticlesTable.colIsFavorite] == 1).toList();
    }

    list.sort(
      (a, b) => (b[ArticlesTable.colPublishedAt] as int).compareTo(
        a[ArticlesTable.colPublishedAt] as int,
      ),
    );
    return list;
  }

  int _update(String sql, List<Object?> args) {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.startsWith('UPDATE articles SET is_read = ? WHERE id = ?')) {
      final row = _rowsById[args[1] as String];
      if (row == null) return 0;
      row[ArticlesTable.colIsRead] = args[0];
      return 1;
    }
    if (normalized.startsWith(
      'UPDATE articles SET is_favorite = ?, favorited_at = ? WHERE id = ?',
    )) {
      final row = _rowsById[args[2] as String];
      if (row == null) return 0;
      row[ArticlesTable.colIsFavorite] = args[0];
      row[ArticlesTable.colFavoritedAt] = args[1];
      return 1;
    }
    return 0;
  }
}
