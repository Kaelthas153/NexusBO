import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/data/repositories/news_repository_impl.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';
import 'package:nexusbo/features/news/domain/sources/multi_source_sync_engine.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';

class _FakeLocalDataSource implements NewsLocalDataSource {
  final Map<String, ArticleModel> _store = <String, ArticleModel>{};

  void seed(List<ArticleModel> articles) {
    for (final a in articles) {
      _store[a.id] = a;
    }
  }

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
    return getArticles(category: category, limit: limit);
  }

  @override
  Future<List<ArticleModel>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    var all = await getLatestArticles(limit: 1000);

    if (category != null &&
        category.trim().isNotEmpty &&
        category.trim().toLowerCase() != 'todas') {
      final canonical = CategoryMapper.toCanonical(category);
      all = all
          .where(
            (a) =>
                a.category.toLowerCase() == category.toLowerCase() ||
                a.category.toLowerCase() == canonical,
          )
          .toList();
    }

    if (sourceId != null &&
        sourceId.trim().isNotEmpty &&
        sourceId.trim().toLowerCase() != 'todas') {
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
  Future<ArticleModel?> getArticleById(String id) async => _store[id];

  @override
  Future<List<ArticleModel>> getFavorites() async {
    final all = await getLatestArticles(limit: 1000);
    return all.where((a) => a.isFavorite).toList(growable: false);
  }

  @override
  Future<void> markAsRead(String id) async {
    final item = _store[id];
    if (item != null) {
      _store[id] = item.copyWith(isRead: true);
    }
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final item = _store[id];
    if (item != null) {
      final newVal = !item.isFavorite;
      _store[id] = item.copyWith(
        isFavorite: newVal,
        favoritedAt: newVal ? DateTime.now().toUtc() : null,
      );
    }
  }

  @override
  Future<List<ArticleModel>> searchArticles(String query, {int limit = 100}) async =>
      <ArticleModel>[];

  @override
  Future<List<ArticleModel>> upsertArticles(List<ArticleModel> articles) async {
    for (final a in articles) {
      _store[a.id] = a;
    }
    return articles;
  }

  @override
  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  }) async => 0;

  @override
  Future<int> clearArticles({bool keepFavorites = false}) async {
    final count = _store.length;
    _store.clear();
    return count;
  }
}

class _DummySource implements NewsSource {
  _DummySource({required this.id, required this.name, this.sortOrder = 1});

  @override
  final String id;
  @override
  final String name;
  @override
  final int sortOrder;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async => const <ArticleModel>[];
}

void main() {
  group('Etapa 6: Filtrado Independiente por Fuente en NexusBO', () {
    late _FakeLocalDataSource localDataSource;
    late NewsRepositoryImpl repository;

    // Artículos de prueba distribuidos entre ABI, DTV y El Deber
    final articleAbiPol = ArticleModel(
      id: 'abi_01',
      sourceId: 'abi',
      sourceName: 'ABI',
      title: 'ABI - Diputados debaten ley',
      summary: 'Resumen ABI politica',
      contentPlain: 'Contenido ABI',
      url: 'https://abi.bo/nota-1',
      author: 'ABI Central',
      tags: const <String>['politica'],
      publishedAt: DateTime.utc(2026, 10, 31, 10, 0),
      fetchedAt: DateTime.utc(2026, 10, 31, 10, 5),
      category: 'politica',
      isFavorite: true,
      isRead: true,
    );

    final articleAbiEcon = ArticleModel(
      id: 'abi_02',
      sourceId: 'abi',
      sourceName: 'ABI',
      title: 'ABI - Inflación y reservas',
      summary: 'Resumen ABI economia',
      contentPlain: 'Contenido ABI',
      url: 'https://abi.bo/nota-2',
      author: 'ABI Central',
      tags: const <String>['economia'],
      publishedAt: DateTime.utc(2026, 10, 31, 9, 0),
      fetchedAt: DateTime.utc(2026, 10, 31, 9, 5),
      category: 'economia',
    );

    final articleDtvPol = ArticleModel(
      id: 'dtv_01',
      sourceId: 'dtv',
      sourceName: 'DTV',
      title: 'DTV - Debate político nocturno',
      summary: 'Resumen DTV politica',
      contentPlain: 'Contenido DTV',
      url: 'https://dtv.bo/nota-1',
      author: 'DTV Redacción',
      tags: const <String>['politica'],
      publishedAt: DateTime.utc(2026, 10, 31, 11, 0),
      fetchedAt: DateTime.utc(2026, 10, 31, 11, 5),
      category: 'politica',
    );

    final articleDtvSoc = ArticleModel(
      id: 'dtv_02',
      sourceId: 'dtv',
      sourceName: 'DTV',
      title: 'DTV - Bloqueo en carreteras',
      summary: 'Resumen DTV sociedad',
      contentPlain: 'Contenido DTV',
      url: 'https://dtv.bo/nota-2',
      author: 'DTV Redacción',
      tags: const <String>['sociedad'],
      publishedAt: DateTime.utc(2026, 10, 31, 8, 0),
      fetchedAt: DateTime.utc(2026, 10, 31, 8, 5),
      category: 'sociedad',
    );

    final articleElDeberEcon = ArticleModel(
      id: 'eldeber_01',
      sourceId: 'eldeber',
      sourceName: 'El Deber',
      title: 'El Deber - Comercio exterior cruceño',
      summary: 'Resumen El Deber economia',
      contentPlain: 'Contenido El Deber',
      url: 'https://eldeber.com.bo/nota-1',
      author: 'EL DEBER',
      tags: const <String>['economia'],
      publishedAt: DateTime.utc(2026, 10, 31, 12, 0),
      fetchedAt: DateTime.utc(2026, 10, 31, 12, 5),
      category: 'economia',
    );

    final articleElDeberSoc = ArticleModel(
      id: 'eldeber_02',
      sourceId: 'eldeber',
      sourceName: 'El Deber',
      title: 'El Deber - Salud y hospitales',
      summary: 'Resumen El Deber sociedad',
      contentPlain: 'Contenido El Deber',
      url: 'https://eldeber.com.bo/nota-2',
      author: 'EL DEBER',
      tags: const <String>['sociedad'],
      publishedAt: DateTime.utc(2026, 10, 31, 7, 0),
      fetchedAt: DateTime.utc(2026, 10, 31, 7, 5),
      category: 'sociedad',
    );

    setUp(() {
      localDataSource = _FakeLocalDataSource();
      localDataSource.seed([
        articleAbiPol,
        articleAbiEcon,
        articleDtvPol,
        articleDtvSoc,
        articleElDeberEcon,
        articleElDeberSoc,
      ]);
      repository = NewsRepositoryImpl(
        localDataSource: localDataSource,
        syncEngine: MultiSourceSyncEngine(registry: NewsSourceRegistry()),
      );
    });

    test('A. Todas + Todas devuelve artículos de ABI, DTV y El Deber', () async {
      final results = await repository.getArticles(
        category: 'Todas',
        sourceId: null,
      );

      expect(results.length, equals(6));
      final sources = results.map((a) => a.sourceId).toSet();
      expect(sources, containsAll(<String>['abi', 'dtv', 'eldeber']));
    });

    test('B. Fuente = ABI devuelve únicamente artículos con source_id == "abi"', () async {
      final results = await repository.getArticles(
        category: null,
        sourceId: 'abi',
      );

      expect(results.length, equals(2));
      expect(results.every((a) => a.sourceId == 'abi'), isTrue);
      expect(results.map((a) => a.id), containsAll(<String>['abi_01', 'abi_02']));
    });

    test('C. Fuente = DTV devuelve únicamente artículos con source_id == "dtv"', () async {
      final results = await repository.getArticles(
        category: 'Todas',
        sourceId: 'dtv',
      );

      expect(results.length, equals(2));
      expect(results.every((a) => a.sourceId == 'dtv'), isTrue);
      expect(results.map((a) => a.id), containsAll(<String>['dtv_01', 'dtv_02']));
    });

    test('D. Fuente = El Deber devuelve únicamente artículos con source_id == "eldeber"', () async {
      final results = await repository.getArticles(
        category: null,
        sourceId: 'eldeber',
      );

      expect(results.length, equals(2));
      expect(results.every((a) => a.sourceId == 'eldeber'), isTrue);
      expect(results.map((a) => a.id), containsAll(<String>['eldeber_01', 'eldeber_02']));
    });

    test('E. Política + DTV devuelve únicamente categoría "politica" y source_id "dtv"', () async {
      final results = await repository.getArticles(
        category: 'Política',
        sourceId: 'dtv',
      );

      expect(results.length, equals(1));
      final article = results.first;
      expect(article.id, equals('dtv_01'));
      expect(article.sourceId, equals('dtv'));
      expect(article.category, equals('politica'));
    });

    test('F. Economía + Todas devuelve artículos de economía de cualquier fuente', () async {
      final results = await repository.getArticles(
        category: 'Economía',
        sourceId: null,
      );

      expect(results.length, equals(2));
      expect(results.every((a) => a.category == 'economia'), isTrue);
      final sources = results.map((a) => a.sourceId).toSet();
      expect(sources, containsAll(<String>['abi', 'eldeber']));
    });

    test('G. Todas + ABI devuelve cualquier categoría pero solo ABI', () async {
      final results = await repository.getArticles(
        category: 'Todas',
        sourceId: 'abi',
      );

      expect(results.length, equals(2));
      expect(results.every((a) => a.sourceId == 'abi'), isTrue);
      final categories = results.map((a) => a.category).toSet();
      expect(categories, containsAll(<String>['politica', 'economia']));
    });

    test('H. Combinación sin resultados devuelve lista vacía sin arrojar error', () async {
      final results = await repository.getArticles(
        category: 'Cultura',
        sourceId: 'dtv',
      );

      expect(results, isEmpty);
      expect(results, isA<List<Article>>());
    });

    test('I. El orden de retorno siempre es publishedAt DESC', () async {
      final results = await repository.getArticles(
        category: 'Todas',
        sourceId: null,
      );

      expect(results.length, equals(6));
      for (int i = 0; i < results.length - 1; i++) {
        expect(
          results[i].publishedAt.isAfter(results[i + 1].publishedAt) ||
              results[i].publishedAt.isAtSameMomentAs(results[i + 1].publishedAt),
          isTrue,
          reason: 'El artículo en índice $i debe ser más reciente o igual al siguiente.',
        );
      }

      // El más reciente en los datos sembrados es eldeber_01 (12:00 UTC)
      expect(results.first.id, equals('eldeber_01'));
      // El segundo más reciente es dtv_01 (11:00 UTC)
      expect(results[1].id, equals('dtv_01'));
      // El tercero más reciente es abi_01 (10:00 UTC)
      expect(results[2].id, equals('abi_01'));
    });

    test('J. Cambiar filtros no modifica favoritos ni isRead de los artículos', () async {
      // abi_01 fue sembrado como isFavorite=true e isRead=true
      final initial = await localDataSource.getArticleById('abi_01');
      expect(initial?.isFavorite, isTrue);
      expect(initial?.isRead, isTrue);

      // Filtro 1: DTV
      final dtvArticles = await repository.getArticles(category: null, sourceId: 'dtv');
      expect(dtvArticles.any((a) => a.id == 'abi_01'), isFalse);

      // Filtro 2: El Deber
      final eldeberArticles = await repository.getArticles(category: 'Economía', sourceId: 'eldeber');
      expect(eldeberArticles.any((a) => a.id == 'abi_01'), isFalse);

      // Volver a ABI
      final abiArticles = await repository.getArticles(category: 'Todas', sourceId: 'abi');
      final foundAbi = abiArticles.firstWhere((a) => a.id == 'abi_01');

      expect(foundAbi.isFavorite, isTrue);
      expect(foundAbi.isRead, isTrue);
    });

    test('K. NewsSourceRegistry genera dinámicamente las opciones visuales de filtro', () {
      final registry = NewsSourceRegistry(initialSources: [
        _DummySource(id: 'abi', name: 'ABI', sortOrder: 1),
        _DummySource(id: 'dtv', name: 'DTV', sortOrder: 2),
        _DummySource(id: 'eldeber', name: 'El Deber', sortOrder: 3),
      ]);

      final options = <SourceFilterOption>[
        const SourceFilterOption(displayName: 'Todas', sourceId: null),
        ...registry.getEnabledSources().map(
          (s) => SourceFilterOption(displayName: s.name, sourceId: s.id),
        ),
      ];

      expect(options.length, equals(4));
      expect(options[0].displayName, equals('Todas'));
      expect(options[0].sourceId, isNull);
      expect(options[1].displayName, equals('ABI'));
      expect(options[1].sourceId, equals('abi'));
      expect(options[2].displayName, equals('DTV'));
      expect(options[2].sourceId, equals('dtv'));
      expect(options[3].displayName, equals('El Deber'));
      expect(options[3].sourceId, equals('eldeber'));
    });
  });
}
