import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/data/repositories/news_repository_impl.dart';
import 'package:nexusbo/features/news/data/sources/dtv_news_source.dart';
import 'package:nexusbo/features/news/data/sources/el_deber_news_source.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/sources/multi_source_sync_engine.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';
import 'package:nexusbo/services/background/background_task_service.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';
import 'package:nexusbo/services/preferences/app_preferences_service.dart';

// Fixture JSON representativo de DTV con UTF-8 BOM (\uFEFF)
const String kDtvSampleJsonWithBom = '''\uFEFF[
  {
    "id": 47978,
    "date": "2026-10-31T03:30:00",
    "date_gmt": "2026-10-31T03:30:00",
    "link": "https://dtv.bo/identifican-a-miguel-angel/?utm_source=rss&utm_medium=rss",
    "title": {
      "rendered": "&#8220;Identifican a joven en La Guardia&#8221;"
    },
    "content": {
      "rendered": "<p>Contenido completo de la investigación en La Guardia.</p><p><img src=\\"https://dtv.bo/uploads/foto_interna.jpg\\" /></p>"
    },
    "excerpt": {
      "rendered": "<p>El informe preliminar de la Policía confirma la identidad...</p>"
    },
    "_embedded": {
      "author": [
        {"id": 5, "name": "Claudia Cuarite"}
      ],
      "wp:featuredmedia": [
        {"id": 102, "source_url": "https://dtv.bo/uploads/portada_destacada.jpg"}
      ],
      "wp:term": [
        [
          {"id": 12, "name": "POLÍTICA", "taxonomy": "category"},
          {"id": 15, "name": "Seguridad", "taxonomy": "category"}
        ],
        [
          {"id": 88, "name": "Fiscalía", "taxonomy": "post_tag"}
        ]
      ]
    }
  }
]''';

// Fixture RSS 2.0 representativo de El Deber
const String kElDeberSampleRssXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>EL DEBER - Noticias</title>
    <link>https://eldeber.com.bo</link>
    <item>
      <title><![CDATA[Fin de semana largo: levantan cortes en carreteras]]></title>
      <link>https://eldeber.com.bo/pais/fin-semana-largo-levantan-varios-cortes_1793447811</link>
      <guid>https://eldeber.com.bo/pais/fin-semana-largo-levantan-varios-cortes_1793447811</guid>
      <description><![CDATA[<p>De acuerdo con el detalle de transitabilidad de la ABC...</p>]]></description>
      <pubDate>Sat, 31 Oct 2026 11:56:51 GMT</pubDate>
      <enclosure url="https://pxcdn.eldeber.com.bo/eldeber/102026/1793447709917.jpg?cw=320&amp;ch=180" type="image/jpeg" />
    </item>
    <item>
      <title><![CDATA[Reporte sin ID numérico para prueba fallback]]></title>
      <link>https://eldeber.com.bo/economia/reporte-especial-de-mercados</link>
      <guid>https://eldeber.com.bo/economia/reporte-especial-de-mercados</guid>
      <author><![CDATA[None]]></author>
      <description><![CDATA[Análisis sobre la producción nacional.]]></description>
      <pubDate>Sat, 31 Oct 2026 10:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>''';

class _FakeSource implements NewsSource {
  _FakeSource({
    required this.id,
    required this.name,
    this.sortOrder = 10,
    this.articlesToReturn = const <ArticleModel>[],
    this.errorToThrow,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final int sortOrder;

  List<ArticleModel> articlesToReturn;
  final Object? errorToThrow;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return articlesToReturn;
  }
}

class _RecordingNotificationGateway implements NotificationGateway {
  final List<List<Article>> dispatchedBatches = <List<Article>>[];

  @override
  Future<void> initialize({bool isBackgroundIsolate = false}) async {}

  @override
  Future<void> notifyNewArticles(List<Article> newArticles) async {
    dispatchedBatches.add(List<Article>.unmodifiable(newArticles));
  }

  @override
  Future<void> showDebugTestNotification() async {}

  @override
  Future<void> showHourlyReportNotification({
    required String windowLabel,
    required int articleCount,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {}
}

class _FakePreferences extends Fake implements AppPreferencesDataSource {
  _FakePreferences();

  bool notificationsEnabled = true;
  bool cacheClearedPendingBaseline = false;

  @override
  Future<bool> getNotificationsEnabled({bool reload = false}) async =>
      notificationsEnabled;

  @override
  Future<bool> isCacheClearedPendingBaseline({bool reload = false}) async =>
      cacheClearedPendingBaseline;

  @override
  Future<void> setCacheClearedPendingBaseline(bool value) async {
    cacheClearedPendingBaseline = value;
  }

  bool hourlyReportsEnabled = false;
  String? lastHourlyWindow;
  bool reportSourcesModeAll = true;
  List<String> reportSelectedSourceIds = const <String>[];

  @override
  Future<bool> getHourlyReportsEnabled({bool reload = false}) async =>
      hourlyReportsEnabled;

  @override
  Future<void> setHourlyReportsEnabled(bool enabled) async {
    hourlyReportsEnabled = enabled;
  }

  @override
  Future<String?> getLastHourlyReportWindowNotified({bool reload = false}) async =>
      lastHourlyWindow;

  @override
  Future<void> setLastHourlyReportWindowNotified(String windowId) async {
    lastHourlyWindow = windowId;
  }

  @override
  Future<bool> getReportSourcesModeAll({bool reload = false}) async =>
      reportSourcesModeAll;

  @override
  Future<void> setReportSourcesModeAll(bool isAll) async {
    reportSourcesModeAll = isAll;
  }

  @override
  Future<List<String>> getReportSelectedSourceIds({bool reload = false}) async =>
      reportSelectedSourceIds;

  @override
  Future<void> setReportSelectedSourceIds(List<String> sourceIds) async {
    reportSelectedSourceIds = sourceIds;
  }

  bool backgroundSyncEnabled = true;
  final Set<String> _seededSources = <String>{};

  @override
  Future<bool> getBackgroundSyncEnabled({bool reload = false}) async =>
      backgroundSyncEnabled;

  @override
  Future<void> setBackgroundSyncEnabled(bool enabled) async {
    backgroundSyncEnabled = enabled;
  }

  @override
  Future<Set<String>> getSeededSourceIds({bool reload = false}) async =>
      Set<String>.from(_seededSources);

  @override
  Future<void> setSourceSeeded(String sourceId) async {
    _seededSources.add(sourceId);
  }

  @override
  Future<void> clearSeededSources() async {
    _seededSources.clear();
  }
}

class _InMemoryNewsLocalDataSource implements NewsLocalDataSource {
  final Map<String, ArticleModel> _store = <String, ArticleModel>{};

  @override
  Future<List<ArticleModel>> getLatestArticles({int limit = 100}) async {
    final list = _store.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return list.take(limit).toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticlesByCategory(
    String category, {
    int limit = 100,
  }) async {
    final all = await getLatestArticles(limit: limit);
    final canonical = CategoryMapper.toCanonical(category);
    return all
        .where(
          (a) =>
              a.category == canonical ||
              CategoryMapper.toCanonical(a.category) == canonical,
        )
        .toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    var all = await getLatestArticles(limit: 1000);
    if (category != null && category.trim().isNotEmpty && category.toLowerCase() != 'todas') {
      final canonical = CategoryMapper.toCanonical(category);
      all = all
          .where(
            (a) =>
                a.category == canonical ||
                CategoryMapper.toCanonical(a.category) == canonical,
          )
          .toList();
    }
    if (sourceId != null && sourceId.trim().isNotEmpty && sourceId.toLowerCase() != 'todas') {
      all = all.where((a) => a.sourceId == sourceId).toList();
    }
    return all.skip(offset).take(limit).toList(growable: false);
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
    final lower = query.toLowerCase();
    final all = await getLatestArticles(limit: limit);
    return all
        .where(
          (a) =>
              a.title.toLowerCase().contains(lower) ||
              a.summary.toLowerCase().contains(lower),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ArticleModel>> getFavorites() async {
    final all = await getLatestArticles();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NewsLocalDataSource localDataSource;

  setUp(() {
    localDataSource = _InMemoryNewsLocalDataSource();
  });

  group('Etapa 5: Arquitectura Multi-Source (ABI + DTV + El Deber)', () {
    // -------------------------------------------------------------------------
    // 1. DTV
    // -------------------------------------------------------------------------
    test('A. DtvNewsSource parsea JSON con BOM UTF-8, featured image y categorías', () {
      final dtvSource = DtvNewsSource(dioClient: DioClient());
      final articles = dtvSource.parseJsonPosts(
        kDtvSampleJsonWithBom,
        fetchedAtOverrideUtc: DateTime.utc(2026, 10, 31, 4, 0),
      );

      expect(articles.length, 1);
      final a = articles.first;

      expect(a.id, 'dtv_47978');
      expect(a.sourceId, 'dtv');
      expect(a.sourceName, 'DTV');
      expect(a.title, '“Identifican a joven en La Guardia”');
      expect(a.author, 'Claudia Cuarite');
      expect(a.category, 'politica'); // Canonical de 'POLÍTICA'
      expect(a.publishedAt, DateTime.utc(2026, 10, 31, 3, 30));
      expect(a.imageUrl, 'https://dtv.bo/uploads/portada_destacada.jpg');
      expect(a.imageUrls, contains('https://dtv.bo/uploads/portada_destacada.jpg'));
      expect(a.imageUrls, contains('https://dtv.bo/uploads/foto_interna.jpg'));
      expect(a.summary, contains('El informe preliminar de la Policía'));
      expect(a.contentPlain, contains('Contenido completo de la investigación'));
      expect(a.url, 'https://dtv.bo/identifican-a-miguel-angel/'); // Limpio sin utm_*
    });

    // -------------------------------------------------------------------------
    // 2. El Deber
    // -------------------------------------------------------------------------
    test('B. ElDeberNewsSource parsea RSS con enclosure, deduce ID numérico y categoría de URL', () {
      final edSource = ElDeberNewsSource(dioClient: DioClient());
      final articles = edSource.parseRssXml(
        kElDeberSampleRssXml,
        fetchedAtOverrideUtc: DateTime.utc(2026, 10, 31, 12, 0),
      );

      expect(articles.length, 2);

      // Ítem 1: con ID numérico en URL y enclosure
      final a1 = articles[0];
      expect(a1.id, 'eldeber_1793447811');
      expect(a1.sourceId, 'eldeber');
      expect(a1.sourceName, 'El Deber');
      expect(a1.title, 'Fin de semana largo: levantan cortes en carreteras');
      expect(a1.imageUrl, 'https://pxcdn.eldeber.com.bo/eldeber/102026/1793447709917.jpg?cw=320&ch=180');
      expect(a1.imageUrls.single, a1.imageUrl);
      expect(a1.author, 'EL DEBER');
      expect(a1.category, 'sociedad'); // /pais/ -> sociedad
      expect(a1.summary, contains('De acuerdo con el detalle de transitabilidad'));

      // Ítem 2: sin ID numérico -> fallback determinista y autor fallback
      final a2 = articles[1];
      expect(a2.id, startsWith('eldeber_'));
      expect(a2.id, isNot('eldeber_'));
      expect(a2.author, 'EL DEBER'); // Fallback en vez de 'None'
      expect(a2.category, 'economia'); // /economia/ -> economia
    });

    // -------------------------------------------------------------------------
    // 3. CategoryMapper
    // -------------------------------------------------------------------------
    test('C. CategoryMapper normaliza categorías y proporciona nombres de visualización', () {
      expect(CategoryMapper.toCanonical('Política'), 'politica');
      expect(CategoryMapper.toCanonical('POLÍTICA'), 'politica');
      expect(CategoryMapper.toCanonical('Economía'), 'economia');
      expect(CategoryMapper.toCanonical('seguridad'), 'seguridad');
      expect(CategoryMapper.toCanonical('policial'), 'seguridad');
      expect(CategoryMapper.toCanonical('/pais/'), 'sociedad');
      expect(CategoryMapper.toCanonical('santa-cruz'), 'sociedad');
      expect(CategoryMapper.toCanonical('marcas'), 'deportes');
      expect(CategoryMapper.toCanonical('entretenimiento'), 'cultura');
      expect(CategoryMapper.toCanonical('mundo'), 'general');

      expect(CategoryMapper.toDisplay('politica'), 'Política');
      expect(CategoryMapper.toDisplay('economia'), 'Economía');
      expect(CategoryMapper.toDisplay('seguridad'), 'Seguridad');
      expect(CategoryMapper.toDisplay('sociedad'), 'Sociedad');
      expect(CategoryMapper.toDisplay('deportes'), 'Deportes');
      expect(CategoryMapper.toDisplay('cultura'), 'Cultura');
      expect(CategoryMapper.toDisplay('general'), 'General');
    });

    // -------------------------------------------------------------------------
    // 4. Aislamiento de Fallos en MultiSourceSyncEngine
    // -------------------------------------------------------------------------
    test('D. MultiSourceSyncEngine aísla el fallo de una fuente sin bloquear a las demás', () async {
      final registry = NewsSourceRegistry();
      registry.register(_FakeSource(
        id: 'abi',
        name: 'ABI',
        sortOrder: 1,
        articlesToReturn: <ArticleModel>[
          ArticleModel(
            id: 'abi_1',
            title: 'Noticia ABI',
            summary: 'Resumen ABI',
            contentPlain: 'Cuerpo ABI',
            url: 'https://abi.bo/1',
            author: 'ABI',
            sourceId: 'abi',
            sourceName: 'ABI',
            category: 'politica',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 10),
            fetchedAt: DateTime.utc(2026, 10, 31, 10),
          ),
        ],
      ));

      // DTV simula fallo de red
      registry.register(_FakeSource(
        id: 'dtv',
        name: 'DTV',
        sortOrder: 2,
        errorToThrow: const NetworkException('Error de conexión con DTV'),
      ));

      // El Deber responde correctamente
      registry.register(_FakeSource(
        id: 'eldeber',
        name: 'El Deber',
        sortOrder: 3,
        articlesToReturn: <ArticleModel>[
          ArticleModel(
            id: 'eldeber_1',
            title: 'Noticia El Deber',
            summary: 'Resumen ED',
            contentPlain: 'Cuerpo ED',
            url: 'https://eldeber.com.bo/1',
            author: 'EL DEBER',
            sourceId: 'eldeber',
            sourceName: 'El Deber',
            category: 'economia',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 11),
            fetchedAt: DateTime.utc(2026, 10, 31, 11),
          ),
        ],
      ));

      final engine = MultiSourceSyncEngine(
        registry: registry,
        maxConcurrency: 2,
        perSourceTimeout: const Duration(seconds: 5),
      );

      final results = await engine.fetchAllSources();
      expect(results.length, 3);

      final abiResult = results.firstWhere((r) => r.sourceId == 'abi');
      final dtvResult = results.firstWhere((r) => r.sourceId == 'dtv');
      final edResult = results.firstWhere((r) => r.sourceId == 'eldeber');

      expect(abiResult.isSuccess, isTrue);
      expect(abiResult.fetched, 1);

      expect(dtvResult.hasError, isTrue);
      expect(dtvResult.error, isA<NetworkException>());
      expect(dtvResult.fetched, 0);

      expect(edResult.isSuccess, isTrue);
      expect(edResult.fetched, 1);
    });

    // -------------------------------------------------------------------------
    // 5. Integración Multi-Source en NewsRepository
    // -------------------------------------------------------------------------
    test('E. NewsRepository persiste noticias de ABI + DTV + El Deber ordenadas por fecha', () async {
      final registry = NewsSourceRegistry();
      registry.register(_FakeSource(
        id: 'abi',
        name: 'ABI',
        articlesToReturn: <ArticleModel>[
          ArticleModel(
            id: 'abi_100',
            title: 'Noticia ABI 100',
            summary: 'Resumen ABI',
            contentPlain: 'Texto',
            url: 'https://abi.bo/100',
            author: 'ABI',
            sourceId: 'abi',
            sourceName: 'ABI',
            category: 'politica',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 10, 0),
            fetchedAt: DateTime.utc(2026, 10, 31, 10, 0),
          ),
        ],
      ));

      registry.register(_FakeSource(
        id: 'dtv',
        name: 'DTV',
        articlesToReturn: <ArticleModel>[
          ArticleModel(
            id: 'dtv_200',
            title: 'Noticia DTV 200',
            summary: 'Resumen DTV',
            contentPlain: 'Texto DTV',
            url: 'https://dtv.bo/200',
            author: 'DTV',
            sourceId: 'dtv',
            sourceName: 'DTV',
            category: 'seguridad',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 12, 0), // Más reciente
            fetchedAt: DateTime.utc(2026, 10, 31, 12, 0),
          ),
        ],
      ));

      registry.register(_FakeSource(
        id: 'eldeber',
        name: 'El Deber',
        articlesToReturn: <ArticleModel>[
          ArticleModel(
            id: 'eldeber_300',
            title: 'Noticia El Deber 300',
            summary: 'Resumen ED',
            contentPlain: 'Texto ED',
            url: 'https://eldeber.com.bo/300',
            author: 'EL DEBER',
            sourceId: 'eldeber',
            sourceName: 'El Deber',
            category: 'sociedad',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 11, 0), // Intermedio
            fetchedAt: DateTime.utc(2026, 10, 31, 11, 0),
          ),
        ],
      ));

      final engine = MultiSourceSyncEngine(registry: registry);
      final repo = NewsRepositoryImpl(
        localDataSource: localDataSource,
        syncEngine: engine,
      );

      final syncResult = await repo.syncLatestArticles();
      expect(syncResult.fetched, 3);
      expect(syncResult.inserted, 3);

      final latest = await repo.getLatestArticles();
      expect(latest.length, 3);

      // Orden descendente por publishedAt: DTV (12h) -> El Deber (11h) -> ABI (10h)
      expect(latest[0].id, 'dtv_200');
      expect(latest[0].sourceName, 'DTV');
      expect(latest[1].id, 'eldeber_300');
      expect(latest[1].sourceName, 'El Deber');
      expect(latest[2].id, 'abi_100');
      expect(latest[2].sourceName, 'ABI');

      // Filtrado por categoría canónica
      final politicas = await repo.getArticlesByCategory('politica');
      expect(politicas.length, 1);
      expect(politicas.single.id, 'abi_100');

      final seguridad = await repo.getArticlesByCategory('Seguridad');
      expect(seguridad.length, 1);
      expect(seguridad.single.id, 'dtv_200');

      // Favorito sobrevive un nuevo sync
      await repo.toggleFavorite('eldeber_300');
      await repo.markAsRead('dtv_200');

      await repo.syncLatestArticles();

      final edPostSync = await repo.getArticleById('eldeber_300');
      final dtvPostSync = await repo.getArticleById('dtv_200');

      expect(edPostSync?.isFavorite, isTrue);
      expect(dtvPostSync?.isRead, isTrue);
    });

    // -------------------------------------------------------------------------
    // 6. Anti-Spam y Notificaciones en Background Sync Multi-Source
    // -------------------------------------------------------------------------
    test('F. Base vacía con 3 fuentes no dispara notificaciones; sincronización posterior sí', () async {
      final registry = NewsSourceRegistry();
      final fakeSource = _FakeSource(
        id: 'abi',
        name: 'ABI',
        articlesToReturn: <ArticleModel>[
          ArticleModel(
            id: 'seed_1',
            title: 'Noticia Semilla',
            summary: 'Resumen',
            contentPlain: 'Cuerpo',
            url: 'https://abi.bo/seed',
            author: 'ABI',
            sourceId: 'abi',
            sourceName: 'ABI',
            category: 'politica',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 8),
            fetchedAt: DateTime.utc(2026, 10, 31, 8),
          ),
        ],
      );
      final fakeElDeber = _FakeSource(
        id: 'eldeber',
        name: 'El Deber',
        articlesToReturn: <ArticleModel>[
          ArticleModel(
            id: 'eldeber_seed',
            title: 'Semilla El Deber',
            summary: 'Resumen inicial',
            contentPlain: 'Cuerpo inicial',
            url: 'https://eldeber.com.bo/seed',
            author: 'EL DEBER',
            sourceId: 'eldeber',
            sourceName: 'El Deber',
            category: 'economia',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 8),
            fetchedAt: DateTime.utc(2026, 10, 31, 8),
          ),
        ],
      );
      registry.register(fakeSource);
      registry.register(fakeElDeber);

      final engine = MultiSourceSyncEngine(registry: registry);
      final repo = NewsRepositoryImpl(
        localDataSource: localDataSource,
        syncEngine: engine,
      );
      final prefs = _FakePreferences();
      final notifGateway = _RecordingNotificationGateway();

      final orchestrator = BackgroundSyncOrchestrator(
        repository: repo,
        preferences: prefs,
        notificationGateway: notifGateway,
      );

      // Primera sincronización en base vacía (semilla de ambas fuentes)
      final result1 = await orchestrator.executeBackgroundSync();
      expect(result1.wasInitialOrPostClearSeed, isTrue);
      expect(result1.notificationsDispatched, isFalse);
      expect(notifGateway.dispatchedBatches, isEmpty);

      // Segunda sincronización con una noticia nueva de El Deber
      fakeElDeber.articlesToReturn = <ArticleModel>[
        ArticleModel(
          id: 'eldeber_new',
          title: 'Nueva Noticia El Deber',
          summary: 'Resumen nuevo',
          contentPlain: 'Cuerpo nuevo',
          url: 'https://eldeber.com.bo/new',
          author: 'EL DEBER',
          sourceId: 'eldeber',
          sourceName: 'El Deber',
          category: 'economia',
          tags: const <String>[],
          publishedAt: DateTime.utc(2026, 10, 31, 9),
          fetchedAt: DateTime.utc(2026, 10, 31, 9),
        ),
      ];

      final result2 = await orchestrator.executeBackgroundSync();
      expect(result2.wasInitialOrPostClearSeed, isFalse);
      expect(result2.notificationsDispatched, isTrue);
      expect(notifGateway.dispatchedBatches.length, 1);
      expect(notifGateway.dispatchedBatches.single.single.id, 'eldeber_new');
      expect(notifGateway.dispatchedBatches.single.single.sourceName, 'El Deber');
    });

    // -------------------------------------------------------------------------
    // 7. Notificaciones con formato Multi-Source (sin 'ABI' hardcodeado)
    // -------------------------------------------------------------------------
    test('G. NotificationService formatea correctamente body con fuente y categoría canónica', () {
      final articleDtv = Article(
        id: 'dtv_1',
        title: 'Noticia DTV',
        summary: 'Resumen',
        contentPlain: 'Cuerpo',
        url: 'https://dtv.bo/1',
        author: 'DTV',
        sourceId: 'dtv',
        sourceName: 'DTV',
        category: 'politica',
        tags: const <String>[],
        publishedAt: DateTime.utc(2026, 10, 31),
        fetchedAt: DateTime.utc(2026, 10, 31),
      );

      final plan = NotificationService.buildDispatchPlan([articleDtv]);
      expect(plan.notifications.length, 1);
      expect(plan.notifications.single.body, 'DTV • Política');
    });
  });
}
