import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/data/sources/abi_news_source.dart';
import 'package:nexusbo/features/news/data/sources/dtv_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_deber_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_diario_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_pais_news_source.dart';
import 'package:nexusbo/features/news/data/sources/la_razon_news_source.dart';
import 'package:nexusbo/features/news/domain/sources/multi_source_sync_engine.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';

// -----------------------------------------------------------------------------
// FAKES EN MEMORIA PARA PRUEBAS SIN RED NI SQLITE NATIVO
// -----------------------------------------------------------------------------

class _InMemoryNewsLocalDataSource implements NewsLocalDataSource {
  final Map<String, ArticleModel> _db = <String, ArticleModel>{};

  @override
  Future<List<ArticleModel>> getLatestArticles({int limit = 100}) async {
    final list = _db.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return list.take(limit).toList();
  }

  @override
  Future<List<ArticleModel>> getArticlesByCategory(
    String category, {
    int limit = 100,
  }) async {
    final canonical = CategoryMapper.toCanonical(category);
    final list = _db.values
        .where((a) => a.category.toLowerCase() == canonical)
        .toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return list.take(limit).toList();
  }

  @override
  Future<List<ArticleModel>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    var items = _db.values.toList();

    if (category != null &&
        category.trim().isNotEmpty &&
        category.toLowerCase() != 'todas') {
      final canonical = CategoryMapper.toCanonical(category);
      items = items
          .where((a) => a.category.toLowerCase() == canonical)
          .toList();
    }

    if (sourceId != null &&
        sourceId.trim().isNotEmpty &&
        sourceId.toLowerCase() != 'todas') {
      final target = sourceId.trim().toLowerCase();
      items = items
          .where((a) => a.sourceId.toLowerCase() == target)
          .toList();
    }

    items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    if (offset >= items.length) return <ArticleModel>[];
    return items.skip(offset).take(limit).toList();
  }

  @override
  Future<List<ArticleModel>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async {
    final normalizedIds = sourceIds.map((s) => s.trim().toLowerCase()).toSet();
    final list = _db.values.where((article) {
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
  Future<List<ArticleModel>> searchArticles(String query, {int limit = 100}) async {
    final q = query.toLowerCase();
    final list = _db.values
        .where((a) => a.title.toLowerCase().contains(q) || a.contentPlain.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return list.take(limit).toList();
  }

  @override
  Future<List<ArticleModel>> getFavorites() async {
    final list = _db.values.where((a) => a.isFavorite).toList()
      ..sort((a, b) => (b.favoritedAt ?? b.publishedAt).compareTo(a.favoritedAt ?? a.publishedAt));
    return list;
  }

  @override
  Future<ArticleModel?> getArticleById(String id) async => _db[id];

  @override
  Future<void> markAsRead(String id) async {
    final existing = _db[id];
    if (existing != null) {
      _db[id] = existing.copyWith(isRead: true);
    }
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final existing = _db[id];
    if (existing != null) {
      final nextFav = !existing.isFavorite;
      _db[id] = existing.copyWith(
        isFavorite: nextFav,
        favoritedAt: nextFav ? DateTime.now().toUtc() : null,
      );
    }
  }

  @override
  Future<List<ArticleModel>> upsertArticles(List<ArticleModel> articles) async {
    final newArticles = <ArticleModel>[];
    for (final article in articles) {
      final existing = _db[article.id];
      if (existing == null) {
        _db[article.id] = article;
        newArticles.add(article);
      } else {
        _db[article.id] = article.copyWith(
          isFavorite: existing.isFavorite,
          favoritedAt: existing.favoritedAt,
          isRead: existing.isRead,
        );
      }
    }
    return newArticles;
  }

  @override
  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  }) async {
    final cutoff = (referenceTimeUtc ?? DateTime.now().toUtc()).subtract(retentionPeriod);
    var pruned = 0;
    _db.removeWhere((id, article) {
      if (!article.isFavorite && article.publishedAt.isBefore(cutoff)) {
        pruned++;
        return true;
      }
      return false;
    });
    return pruned;
  }

  @override
  Future<int> clearArticles({bool keepFavorites = false}) async {
    var count = 0;
    if (keepFavorites) {
      _db.removeWhere((id, article) {
        if (!article.isFavorite) {
          count++;
          return true;
        }
        return false;
      });
    } else {
      count = _db.length;
      _db.clear();
    }
    return count;
  }
}

// -----------------------------------------------------------------------------
// FIXTURES XML LOCALES
// -----------------------------------------------------------------------------

const String kLaRazonRssFixture = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
	<title>La Razón</title>
	<link>https://larazon.bo/</link>
	<item>
		<title>Ivirgarzama: Enfrentamiento entre sindicatos deja una vivienda calcinada</title>
		<link>https://larazon.bo/nacional/2026/10/31/ivirgarzama-enfrentamiento-entre-sindicatos/</link>
		<dc:creator><![CDATA[Andrea Condori]]></dc:creator>
		<pubDate>Sat, 31 Oct 2026 13:45:07 +0000</pubDate>
		<category><![CDATA[Nacional]]></category>
		<guid isPermaLink="false">https://larazon.bo/?p=273886</guid>
		<description><![CDATA[<p>El enfrentamiento ocurrió la noche del viernes en el trópico.</p>
<p>The post <a href="...">Ivirgarzama</a> appeared first on <a href="...">La Razón</a>.</p>]]></description>
		<content:encoded><![CDATA[<p>Un conflicto entre los sindicatos provocó la quema de una vivienda.</p>
<p>Se espera un reporte de la Policía para esclarecer lo ocurrido.</p>
<p>The post <a href="...">Ivirgarzama</a> appeared first on <a href="...">La Razón</a>.</p>]]></content:encoded>
	</item>
	<item>
		<title>Crisis energética y tarifas en el sector industrial</title>
		<link>https://larazon.bo/economia/2026/10/31/crisis-energetica-y-tarifas/</link>
		<dc:creator><![CDATA[Redacción Central]]></dc:creator>
		<pubDate>Sat, 31 Oct 2026 12:30:00 +0000</pubDate>
		<category><![CDATA[Economía]]></category>
		<guid isPermaLink="false">https://larazon.bo/?p=273890</guid>
		<description><![CDATA[<p>El sector industrial analiza el impacto de nuevos costos.</p>]]></description>
		<content:encoded><![CDATA[<p>Representantes del sector privado emitieron un comunicado urgente.</p>
<p><img src="https://larazon.bo/wp-content/uploads/2026/10/industria.jpg" alt="Industria" /></p>]]></content:encoded>
	</item>
</channel>
</rss>''';

const String kElDiarioRssFixture = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
	<title>El Diario – Bolivia</title>
	<link>https://www.eldiario.net/portal/</link>
	<item>
		<title>Conflicto en límites departamentales moviliza a comunarios</title>
		<link>https://www.eldiario.net/portal/2026/10/30/conflicto-en-limites-departamentales-moviliza-a-comunarios/</link>
		<dc:creator><![CDATA[Viviana Monrroy]]></dc:creator>
		<pubDate>Fri, 30 Oct 2026 23:44:12 +0000</pubDate>
		<category><![CDATA[Sociedad - Seguridad]]></category>
		<guid isPermaLink="false">https://www.eldiario.net/portal/?p=443653</guid>
		<description><![CDATA[<p>Comunarios piden intervención del Viceministerio de Autonomías.</p>
<p>La entrada <a href="...">Conflicto</a> se publicó primero en <a href="...">El Diario - Bolivia</a>.</p>]]></description>
		<content:encoded><![CDATA[<p>Pobladores instalaron un bloqueo en la carretera troncal exigiendo delimitación.</p>
<p><img src="https://www.eldiario.net/portal/wp-content/uploads/2026/10/bloqueo.jpg" alt="Bloqueo" /></p>
<p>La entrada <a href="...">Conflicto</a> se publicó primero en <a href="...">El Diario - Bolivia</a>.</p>]]></content:encoded>
	</item>
	<item>
		<title>Análisis: Desafíos fiscales de cara al cierre de gestión</title>
		<link>https://www.eldiario.net/portal/2026/10/30/desafios-fiscales-cierre-gestion/</link>
		<dc:creator><![CDATA[Mariana Garnica]]></dc:creator>
		<pubDate>Fri, 30 Oct 2026 21:00:00 +0000</pubDate>
		<category><![CDATA[Economía]]></category>
		<guid isPermaLink="false">https://www.eldiario.net/portal/?p=443655</guid>
		<description><![CDATA[<p>Especialistas debaten la política tributaria nacional.</p>]]></description>
		<content:encoded><![CDATA[<p>El déficit fiscal demanda medidas coordinadas con las regiones.</p>]]></content:encoded>
	</item>
</channel>
</rss>''';

const String kElPaisSitemapFixture = '''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
	xmlns:news="http://www.google.com/schemas/sitemap-news/0.9"
	xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
    <url>
        <loc>https://elpais.bo/nacional/20261031_tensa-sesion-declara-a-castro-como-presidente-de-la-camara-de-diputados.html</loc>
        <news:news>
            <news:publication>
                <news:name>El País</news:name>
                <news:language>es</news:language>
            </news:publication>
            <news:publication_date>2026-10-31T00:55:57-04:00</news:publication_date>
            <news:title>Tensa sesión declara a Castro como presidente de la Cámara de Diputados</news:title>
            <news:keywords>Nacional,Cámara de Diputados,Roberto Castro</news:keywords>
        </news:news>
        <image:image>
            <image:loc>https://elpais.bo/img/images_150/contents/2026/10/31/castro_foto.jpg</image:loc>
        </image:image>
    </url>
    <url>
        <loc>https://elpais.bo/tarija/20261031_agenda-50-50-ofrece-coparticipacion-tributaria.html</loc>
        <news:news>
            <news:publication>
                <news:name>El País</news:name>
                <news:language>es</news:language>
            </news:publication>
            <news:publication_date>2026-10-31T00:43:22-04:00</news:publication_date>
            <news:title>Agenda 50-50: Ofrecen coparticipación tributaria a Tarija</news:title>
            <news:keywords>Tarija,Gobernaciones,Economía,Autonomía</news:keywords>
        </news:news>
        <image:image>
            <image:loc>https://elpais.bo/img/images_150/contents/2026/10/31/tarija_reunion.jpg</image:loc>
        </image:image>
    </url>
</urlset>''';

const String kElPaisArticleDetailHtmlFixture = '''<!DOCTYPE html>
<html>
<head>
    <meta property="og:title" content="Tensa sesión declara a Castro como presidente de la Cámara de Diputados" />
    <meta property="og:description" content="Denuncian que no hubo votación para la elección y se impuso una plancha en la sesión de Diputados." />
    <meta name="author" content="Redacción El País Tarija" />
</head>
<body>
    <article id="ep_post_style" class="uk-article">
        <p><span>La sesión para elegir a la nueva directiva de la Cámara de Diputados quedó marcada por gritos y amagos de pelea.</span></p>
        <p><span>En principio, los diputados fueron convocados a las 17:30 para la sesión de honor.</span></p>
        <p><span>Al finalizar la sesión, parlamentarios de cuatro bancadas advirtieron que no reconocerían a esa directiva.</span></p>
        <p>Tienes acceso libre a 200 notas al mes. Para tener acceso ilimitado adquiere tu Suscripción Digital.</p>
        <p><a href="/suscripcion">Suscríbete ahora</a></p>
    </article>
</body>
</html>''';

void main() {
  group('Etapa 7: Integración de La Razón, El Diario y El País (Multi-Source 6 Medios)', () {
    late DioClient dioClient;
    late _InMemoryNewsLocalDataSource localDataSource;

    setUp(() {
      dioClient = DioClient();
      localDataSource = _InMemoryNewsLocalDataSource();
    });

    // =========================================================================
    // SECCIÓN 28: PRUEBAS — LA RAZÓN
    // =========================================================================
    test('1. LaRazonNewsSource parsea RSS, extrae GUID, contenido completo, autor y categorías', () {
      final source = LaRazonNewsSource(
        dioClient: dioClient,
        localDataSource: localDataSource,
      );

      final articles = source.parseRssXml(kLaRazonRssFixture);

      expect(articles.length, equals(2));

      final first = articles.first;
      expect(first.id, equals('larazon_273886'));
      expect(first.title, contains('Ivirgarzama'));
      expect(first.author, equals('Andrea Condori'));
      expect(first.sourceId, equals('larazon'));
      expect(first.sourceName, equals('La Razón'));
      expect(first.category, equals('sociedad')); // Nacional -> sociedad
      expect(first.summary, contains('El enfrentamiento ocurrió la noche del viernes'));
      expect(first.summary, isNot(contains('The post'))); // Footer Yoast eliminado
      expect(first.contentPlain, contains('Se espera un reporte de la Policía'));
      expect(first.contentPlain, isNot(contains('The post')));
      expect(first.publishedAt.isUtc, isTrue);
      expect(first.publishedAt, equals(DateTime.utc(2026, 10, 31, 13, 45, 7)));

      // Segundo artículo con imagen dentro de content:encoded
      final second = articles[1];
      expect(second.id, equals('larazon_273890'));
      expect(second.category, equals('economia'));
      expect(second.imageUrl, equals('https://larazon.bo/wp-content/uploads/2026/10/industria.jpg'));
    });

    test('2. LaRazonNewsSource extrae og:image desde HTML cuando no hay imagen en contenido', () {
      final source = LaRazonNewsSource(
        dioClient: dioClient,
        localDataSource: localDataSource,
      );

      const sampleHtml = '''
      <html><head>
      <meta property="og:image" content="https://larazon.bo/wp-content/uploads/2026/10/ivirgarzama_portada.webp" />
      </head></html>
      ''';

      final articles = source.parseRssXml(
        kLaRazonRssFixture,
        articlePageHtmlByUrl: {
          'https://larazon.bo/nacional/2026/10/31/ivirgarzama-enfrentamiento-entre-sindicatos/': sampleHtml,
        },
      );

      final first = articles.first;
      expect(first.imageUrl, equals('https://larazon.bo/wp-content/uploads/2026/10/ivirgarzama_portada.webp'));
      expect(first.imageUrls, contains('https://larazon.bo/wp-content/uploads/2026/10/ivirgarzama_portada.webp'));
    });

    test('3. LaRazonNewsSource conserva artículo base si falla segunda petición de imagen', () {
      final source = LaRazonNewsSource(
        dioClient: dioClient,
        localDataSource: localDataSource,
        resolveFeaturedImages: false, // Simula omisión o fallo de red secundario
      );

      final articles = source.parseRssXml(kLaRazonRssFixture);
      final first = articles.first;

      expect(first.imageUrl, isNull);
      expect(first.title, isNotEmpty);
      expect(first.contentPlain, isNotEmpty);
    });

    // =========================================================================
    // SECCIÓN 29: PRUEBAS — EL DIARIO
    // =========================================================================
    test('4. ElDiarioNewsSource parsea RSS con ID fecha+slug, imagen interna y mapeo de categorías', () {
      final source = ElDiarioNewsSource(dioClient: dioClient);

      final articles = source.parseRssXml(kElDiarioRssFixture);

      expect(articles.length, equals(2));

      // Artículo 1: Sociedad - Seguridad -> seguridad
      final first = articles.first;
      expect(
        first.id,
        equals('eldiario_20261030_conflicto-en-limites-departamentales-moviliza-a-comunarios'),
      );
      expect(first.title, contains('Conflicto en límites departamentales'));
      expect(first.author, equals('Viviana Monrroy'));
      expect(first.sourceId, equals('eldiario'));
      expect(first.sourceName, equals('El Diario'));
      expect(first.category, equals('seguridad')); // "Sociedad - Seguridad" -> seguridad
      expect(first.imageUrl, equals('https://www.eldiario.net/portal/wp-content/uploads/2026/10/bloqueo.jpg'));
      expect(first.summary, isNot(contains('La entrada')));
      expect(first.contentPlain, isNot(contains('La entrada')));
      expect(first.publishedAt, equals(DateTime.utc(2026, 10, 30, 23, 44, 12)));

      // Artículo 2: Noticia tipográfica sin imagen (imageUrl == null)
      final second = articles[1];
      expect(second.category, equals('economia'));
      expect(second.imageUrl, isNull);
      expect(second.imageUrls, isEmpty);
      expect(second.contentPlain, contains('El déficit fiscal demanda medidas'));
    });

    // =========================================================================
    // SECCIÓN 30: PRUEBAS — EL PAÍS
    // =========================================================================
    test('5. ElPaisNewsSource parsea Google News Sitemap con namespaces XML, image:loc e ID fecha+slug', () {
      final source = ElPaisNewsSource(
        dioClient: dioClient,
        localDataSource: localDataSource,
        enrichNewArticles: false,
      );

      final articles = source.parseSitemapXml(kElPaisSitemapFixture);

      expect(articles.length, equals(2));

      final first = articles.first;
      expect(
        first.id,
        equals('elpais_20261031_tensa-sesion-declara-a-castro-como-presidente-de-la-camara-de-diputados'),
      );
      expect(first.title, contains('Tensa sesión declara a Castro'));
      expect(first.sourceId, equals('elpais'));
      expect(first.sourceName, equals('El País'));
      expect(first.category, equals('sociedad')); // nacional -> sociedad
      expect(first.imageUrl, equals('https://elpais.bo/img/images_150/contents/2026/10/31/castro_foto.jpg'));
      expect(first.tags, contains('Nacional'));
      expect(first.publishedAt, equals(DateTime.parse('2026-10-31T00:55:57-04:00').toUtc()));

      final second = articles[1];
      expect(second.category, equals('sociedad')); // tarija -> sociedad
      expect(second.imageUrl, equals('https://elpais.bo/img/images_150/contents/2026/10/31/tarija_reunion.jpg'));
    });

    test('6. ElPaisNewsSource enriquece cuerpo completo, og:description y filtra muros de pago', () {
      final source = ElPaisNewsSource(
        dioClient: dioClient,
        localDataSource: localDataSource,
      );

      final articles = source.parseSitemapXml(
        kElPaisSitemapFixture,
        articlePageHtmlByUrl: {
          'https://elpais.bo/nacional/20261031_tensa-sesion-declara-a-castro-como-presidente-de-la-camara-de-diputados.html':
              kElPaisArticleDetailHtmlFixture,
        },
      );

      final first = articles.first;
      // Resumen enriquecido desde og:description
      expect(first.summary, contains('Denuncian que no hubo votación'));
      // Autor enriquecido desde <meta name="author">
      expect(first.author, equals('Redacción El País Tarija'));
      // Cuerpo enriquecido desde párrafos del <article id="ep_post_style">
      expect(first.contentPlain, contains('La sesión para elegir a la nueva directiva'));
      expect(first.contentPlain, contains('En principio, los diputados fueron convocados'));
      // Texto de suscripción eliminado
      expect(first.contentPlain, isNot(contains('Tienes acceso libre a 200 notas')));
      expect(first.contentPlain, isNot(contains('Suscríbete ahora')));
      // Imagen original de sitemap conservada
      expect(first.imageUrl, equals('https://elpais.bo/img/images_150/contents/2026/10/31/castro_foto.jpg'));
    });

    // =========================================================================
    // SECCIÓN 31: PRUEBAS MULTI-SOURCE INTEGRANDO LAS 6 FUENTES
    // =========================================================================
    test('7. NewsSourceRegistry incluye y ordena adecuadamente las 6 fuentes bolivianas', () {
      final registry = NewsSourceRegistry(
        initialSources: <NewsSource>[
          AbiNewsSource(dioClient: dioClient),
          DtvNewsSource(dioClient: dioClient),
          ElDeberNewsSource(dioClient: dioClient),
          LaRazonNewsSource(dioClient: dioClient, localDataSource: localDataSource),
          ElDiarioNewsSource(dioClient: dioClient),
          ElPaisNewsSource(dioClient: dioClient, localDataSource: localDataSource),
        ],
      );

      expect(registry.count, equals(6));
      final all = registry.getAllSources();
      expect(all.map((s) => s.id).toList(), equals(<String>[
        'abi',
        'dtv',
        'eldeber',
        'larazon',
        'eldiario',
        'elpais',
      ]));
      expect(all.map((s) => s.name).toList(), equals(<String>[
        'ABI',
        'DTV',
        'El Deber',
        'La Razón',
        'El Diario',
        'El País',
      ]));
    });

    test('8. MultiSourceSyncEngine ejecuta 6 fuentes respetando concurrencia máxima de 2 o 3', () async {
      var concurrentCount = 0;
      var maxObservedConcurrency = 0;

      NewsSource makeMockSource(String id, String name, int order) {
        return _MockConcurrentSource(
          id: id,
          name: name,
          sortOrder: order,
          onFetch: () async {
            concurrentCount++;
            if (concurrentCount > maxObservedConcurrency) {
              maxObservedConcurrency = concurrentCount;
            }
            await Future<void>.delayed(const Duration(milliseconds: 30));
            concurrentCount--;
            return <ArticleModel>[];
          },
        );
      }

      final testSources = <NewsSource>[
        makeMockSource('abi', 'ABI', 1),
        makeMockSource('dtv', 'DTV', 2),
        makeMockSource('eldeber', 'El Deber', 3),
        makeMockSource('larazon', 'La Razón', 4),
        makeMockSource('eldiario', 'El Diario', 5),
        makeMockSource('elpais', 'El País', 6),
      ];

      final engine = MultiSourceSyncEngine(
        registry: NewsSourceRegistry(initialSources: testSources),
        maxConcurrency: 2,
      );

      final results = await engine.fetchAllSources();

      expect(results.length, equals(6));
      expect(maxObservedConcurrency, lessThanOrEqualTo(2));
      expect(results.every((r) => r.isSuccess), isTrue);
    });

    test('9. NewsRepository persiste incrementalmente las 6 fuentes ordenadas por publishedAt DESC', () async {
      final now = DateTime.now().toUtc();

      final a1 = _buildTestArticle(id: 'abi_1', sourceId: 'abi', sourceName: 'ABI', category: 'politica', publishedAt: now.subtract(const Duration(minutes: 60)));
      final a2 = _buildTestArticle(id: 'dtv_1', sourceId: 'dtv', sourceName: 'DTV', category: 'seguridad', publishedAt: now.subtract(const Duration(minutes: 50)));
      final a3 = _buildTestArticle(id: 'eldeber_1', sourceId: 'eldeber', sourceName: 'El Deber', category: 'economia', publishedAt: now.subtract(const Duration(minutes: 40)));
      final a4 = _buildTestArticle(id: 'larazon_1', sourceId: 'larazon', sourceName: 'La Razón', category: 'politica', publishedAt: now.subtract(const Duration(minutes: 30)));
      final a5 = _buildTestArticle(id: 'eldiario_1', sourceId: 'eldiario', sourceName: 'El Diario', category: 'seguridad', publishedAt: now.subtract(const Duration(minutes: 20)));
      final a6 = _buildTestArticle(id: 'elpais_1', sourceId: 'elpais', sourceName: 'El País', category: 'economia', publishedAt: now.subtract(const Duration(minutes: 10)));

      await localDataSource.upsertArticles([a1, a2, a3, a4, a5, a6]);

      // Consultar todos
      final allArticles = await localDataSource.getArticles();
      expect(allArticles.length, equals(6));
      expect(allArticles.first.id, equals('elpais_1')); // Más reciente primero
      expect(allArticles.last.id, equals('abi_1'));

      // Filtro por fuente individual: La Razón
      final laRazonOnly = await localDataSource.getArticles(sourceId: 'larazon');
      expect(laRazonOnly.length, equals(1));
      expect(laRazonOnly.first.id, equals('larazon_1'));

      // Filtro por fuente individual: El Diario
      final elDiarioOnly = await localDataSource.getArticles(sourceId: 'eldiario');
      expect(elDiarioOnly.length, equals(1));
      expect(elDiarioOnly.first.id, equals('eldiario_1'));

      // Filtro por fuente individual: El País
      final elPaisOnly = await localDataSource.getArticles(sourceId: 'elpais');
      expect(elPaisOnly.length, equals(1));
      expect(elPaisOnly.first.id, equals('elpais_1'));

      // Filtro combinado: Política + La Razón
      final politicaLaRazon = await localDataSource.getArticles(category: 'politica', sourceId: 'larazon');
      expect(politicaLaRazon.length, equals(1));
      expect(politicaLaRazon.first.id, equals('larazon_1'));

      // Filtro combinado: Seguridad + El Diario
      final seguridadElDiario = await localDataSource.getArticles(category: 'seguridad', sourceId: 'eldiario');
      expect(seguridadElDiario.length, equals(1));
      expect(seguridadElDiario.first.id, equals('eldiario_1'));

      // Filtro combinado: Economía + El País
      final economiaElPais = await localDataSource.getArticles(category: 'economia', sourceId: 'elpais');
      expect(economiaElPais.length, equals(1));
      expect(economiaElPais.first.id, equals('elpais_1'));

      // Filtro combinado sin resultados (ej. Deportes + El Diario)
      final vacio = await localDataSource.getArticles(category: 'deportes', sourceId: 'eldiario');
      expect(vacio, isEmpty);
    });

    test('10. Favoritos y estado isRead sobreviven a resincronizaciones en las 6 fuentes', () async {
      final now = DateTime.now().toUtc();
      final art = _buildTestArticle(
        id: 'larazon_100',
        sourceId: 'larazon',
        sourceName: 'La Razón',
        category: 'politica',
        publishedAt: now,
      );

      await localDataSource.upsertArticles([art]);
      await localDataSource.toggleFavorite('larazon_100');
      await localDataSource.markAsRead('larazon_100');

      var fetched = await localDataSource.getArticleById('larazon_100');
      expect(fetched?.isFavorite, isTrue);
      expect(fetched?.isRead, isTrue);

      // Sincronización posterior actualiza contenido pero debe conservar flags
      final updatedArt = art.copyWith(title: 'Título actualizado');
      await localDataSource.upsertArticles([updatedArt]);

      fetched = await localDataSource.getArticleById('larazon_100');
      expect(fetched?.title, equals('Título actualizado'));
      expect(fetched?.isFavorite, isTrue);
      expect(fetched?.isRead, isTrue);
    });

    test('11. Fallo aislado en una fuente (ej. La Razón 403) no interrumpe la sincronización de las demás', () async {
      final sources = <NewsSource>[
        _MockSingleSource(id: 'abi', name: 'ABI', sortOrder: 1, articles: [_buildTestArticle(id: 'abi_1', sourceId: 'abi', sourceName: 'ABI')]),
        _MockSingleSource(id: 'larazon', name: 'La Razón', sortOrder: 4, shouldFail: true),
        _MockSingleSource(id: 'eldiario', name: 'El Diario', sortOrder: 5, articles: [_buildTestArticle(id: 'eldiario_1', sourceId: 'eldiario', sourceName: 'El Diario')]),
      ];

      final engine = MultiSourceSyncEngine(
        registry: NewsSourceRegistry(initialSources: sources),
      );

      final results = await engine.fetchAllSources();
      expect(results.length, equals(3));

      final abiResult = results.firstWhere((r) => r.sourceId == 'abi');
      final lrResult = results.firstWhere((r) => r.sourceId == 'larazon');
      final edResult = results.firstWhere((r) => r.sourceId == 'eldiario');

      expect(abiResult.isSuccess, isTrue);
      expect(abiResult.fetched, equals(1));

      expect(lrResult.hasError, isTrue);
      expect(lrResult.fetched, equals(0));

      expect(edResult.isSuccess, isTrue);
      expect(edResult.fetched, equals(1));
    });
  });
}

// -----------------------------------------------------------------------------
// HELPERS Y MOCKS PARA TESTS
// -----------------------------------------------------------------------------

ArticleModel _buildTestArticle({
  required String id,
  required String sourceId,
  required String sourceName,
  String title = 'Título de prueba',
  String category = 'politica',
  DateTime? publishedAt,
}) {
  final now = DateTime.now().toUtc();
  return ArticleModel(
    id: id,
    title: title,
    summary: 'Resumen editorial',
    contentPlain: 'Cuerpo completo de la noticia',
    url: 'https://example.bo/$id',
    author: sourceName,
    sourceId: sourceId,
    sourceName: sourceName,
    category: category,
    tags: <String>[category],
    publishedAt: publishedAt ?? now,
    fetchedAt: now,
  );
}

class _MockSingleSource implements NewsSource {
  _MockSingleSource({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.articles = const <ArticleModel>[],
    this.shouldFail = false,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final int sortOrder;
  final List<ArticleModel> articles;
  final bool shouldFail;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    if (shouldFail) {
      throw const NetworkException('HTTP 403 Forbidden simulado', statusCode: 403);
    }
    return articles;
  }
}

class _MockConcurrentSource implements NewsSource {
  _MockConcurrentSource({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.onFetch,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final int sortOrder;
  final Future<List<ArticleModel>> Function() onFetch;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() => onFetch();
}
