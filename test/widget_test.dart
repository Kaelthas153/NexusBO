import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexusbo/app/app.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/entities/sync_result.dart';
import 'package:nexusbo/features/news/domain/repositories/news_repository.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';

void main() {
  testWidgets('NexusBO renders editorial home and bottom navigation', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          newsRepositoryProvider.overrideWithValue(_FakeWidgetTestRepository()),
        ],
        child: const NexusBoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('Favoritos'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(
      find.text('Titular de prueba desde repositorio local'),
      findsOneWidget,
    );
  });
}

class _FakeWidgetTestRepository implements NewsRepository {
  static final List<Article> _articles = <Article>[
    Article(
      id: 'abi_test_1',
      title: 'Titular de prueba desde repositorio local',
      summary: 'Resumen editorial para prueba de interfaz.',
      contentPlain: 'Primer párrafo.\n\nSegundo párrafo.',
      url: 'https://abi.bo/test-1/',
      author: 'Redacción Central',
      sourceId: 'abi',
      sourceName: 'ABI',
      category: 'Política',
      tags: const <String>['Bolivia'],
      publishedAt: DateTime.utc(2026, 10, 31, 1, 0),
      fetchedAt: DateTime.utc(2026, 10, 31, 1, 5),
    ),
  ];

  @override
  Future<Article?> getArticleById(String id) async => _articles.first;

  @override
  Future<List<Article>> getArticlesByCategory(
    String category, {
    int limit = 100,
  }) async => _articles;

  @override
  Future<List<Article>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  }) async => _articles;

  @override
  Future<List<Article>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async => _articles;

  @override
  Future<List<Article>> getFavorites() async => const <Article>[];

  @override
  Future<List<Article>> getLatestArticles({int limit = 100}) async => _articles;

  @override
  Future<void> markAsRead(String id) async {}

  @override
  Future<List<Article>> searchArticles(String query, {int limit = 100}) async =>
      _articles;

  @override
  Future<SyncResult> syncLatestArticles() async {
    return SyncResult(
      fetched: 1,
      inserted: 0,
      syncedAt: DateTime.utc(2026, 10, 31, 1, 5),
    );
  }

  @override
  Future<SyncResult> syncSelectedSources([List<NewsSource>? sources]) async {
    return SyncResult(
      fetched: 1,
      inserted: 0,
      syncedAt: DateTime.utc(2026, 10, 31, 1, 5),
    );
  }

  @override
  Future<void> toggleFavorite(String id) async {}

  @override
  Future<int> pruneOldArticles({
    Duration retentionPeriod = const Duration(days: 30),
    DateTime? referenceTimeUtc,
  }) async => 0;

  @override
  Future<int> clearCache({bool keepFavorites = false}) async => 0;
}
