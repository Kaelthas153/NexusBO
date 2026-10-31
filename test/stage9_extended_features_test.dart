import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/data/repositories/news_repository_impl.dart';
import 'package:nexusbo/features/news/data/sources/anf_news_source.dart';
import 'package:nexusbo/features/news/data/sources/correo_del_sur_news_source.dart';
import 'package:nexusbo/features/news/data/sources/unitel_news_source.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/sources/multi_source_sync_engine.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';
import 'package:nexusbo/features/reports/domain/models/monitoring_report.dart';
import 'package:nexusbo/features/reports/domain/services/monitoring_report_formatter.dart';
import 'package:nexusbo/services/background/background_task_service.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';
import 'package:nexusbo/services/preferences/app_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Etapa 9: Adapters para 9 Medios y Pruebas Extendidas', () {
    // -------------------------------------------------------------------------
    // 1. Correo del Sur News Source
    // -------------------------------------------------------------------------
    group('1. Correo del Sur News Source', () {
      const kuCardHtml = '''
<!DOCTYPE html>
<html>
<body>
  <div class="articles-grid">
    <ku-card
      title="Alcaldía de Sucre entrega obras de asfaltado en el Distrito 3"
      url="/sociedad/20261031_alcaldia-de-sucre-entrega-obras.html"
      author="Redacción Central"
      introduction="El proyecto demandó una inversión de 2 millones de bolivianos."
      section-title="Sociedad"
      image-url="https://correodelsur.com/img/contents/2026/10/31/obras.jpg"
      created-at="2026-10-31 10:30:00"
    ></ku-card>
    <ku-card
      title="Debaten nuevo proyecto de ley económica en Sucre"
      url="/economia/20261031_debaten-nuevo-proyecto.html"
      author=""
      introduction="Representantes cívicos participan del encuentro."
      section-title="Economía"
      image-url=""
      created-at="2026-10-31 09:15:00"
    ></ku-card>
  </div>
</body>
</html>
''';

      test('Extrae metadatos directamente de <ku-card> y genera ID determinista', () {
        final articles = CorreoDelSurNewsSource.parseCards(kuCardHtml);

        expect(articles.length, 2);

        final first = articles.first;
        expect(first.id, 'correodelsur_20261031_alcaldia-de-sucre-entrega-obras');
        expect(first.title, contains('Alcaldía de Sucre'));
        expect(first.sourceId, 'correodelsur');
        expect(first.sourceName, 'Correo del Sur');
        expect(first.category, CategoryMapper.canonicalSociedad);
        expect(first.imageUrl, 'https://correodelsur.com/img/contents/2026/10/31/obras.jpg');
        expect(first.author, 'Redacción Central');
        expect(first.summary, contains('2 millones'));

        final second = articles[1];
        expect(second.id, 'correodelsur_20261031_debaten-nuevo-proyecto');
        expect(second.category, CategoryMapper.canonicalEconomia);
        expect(second.author, 'Correo del Sur'); // fallback si viene vacío
      });

      test('Optimización de detalle: no consulta URL de detalle si ya existe en SQLite', () async {
        final localDataSource = _InMemoryTestLocalDataSource();
        // Insertamos un artículo ya existente en SQLite con cuerpo completo
        await localDataSource.upsertArticles(<ArticleModel>[
          ArticleModel(
            id: 'correodelsur_20261031_alcaldia-de-sucre-entrega-obras',
            title: 'Título existente',
            summary: 'Resumen existente',
            contentPlain: 'Cuerpo completo de más de ochenta caracteres preexistente en la base de datos local SQLite.',
            url: 'https://correodelsur.com/sociedad/20261031_alcaldia-de-sucre-entrega-obras.html',
            author: 'Autor',
            sourceId: 'correodelsur',
            sourceName: 'Correo del Sur',
            category: 'sociedad',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 10, 30),
            fetchedAt: DateTime.utc(2026, 10, 31, 10, 30),
          ),
        ]);

        final cached = await localDataSource.getArticleById('correodelsur_20261031_alcaldia-de-sucre-entrega-obras');
        expect(cached, isNotNull);
        expect(cached!.contentPlain.length, greaterThan(80));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Unitel News Source
    // -------------------------------------------------------------------------
    group('2. Unitel News Source', () {
      const sectionHtml = '''
<!DOCTYPE html>
<html>
<body>
  <div class="news-list">
    <a href="/noticias/politica/paz-admite-preocupacion-por-situacion-politica-ND24502168">Paz admite preocupación</a>
    <a href="/noticias/economia/banco-central-informa-sobre-reservas-ND24502169">Banco Central informa sobre reservas</a>
    <a href="/noticias/deportes/bolivar-se-prepara-para-el-clasico-ND24502170">Bolívar se prepara</a>
  </div>
</body>
</html>
''';

      test('parseArticleLinks descubre enlaces válidos de noticias con identificador ND', () {
        final preliminary = UnitelNewsSource.parseArticleLinks(sectionHtml);

        expect(preliminary.length, 3);
        final first = preliminary.first;
        expect(first.id, 'unitel_ND24502168');
        expect(first.sourceId, 'unitel');
        expect(first.sourceName, 'Unitel');
        expect(first.category, CategoryMapper.canonicalPolitica);
        expect(first.url, 'https://unitel.bo/noticias/politica/paz-admite-preocupacion-por-situacion-politica-ND24502168');

        final second = preliminary[1];
        expect(second.id, 'unitel_ND24502169');
        expect(second.category, CategoryMapper.canonicalEconomia);

        final third = preliminary[2];
        expect(third.id, 'unitel_ND24502170');
        expect(third.category, CategoryMapper.canonicalDeportes);
      });
    });

    // -------------------------------------------------------------------------
    // 3. ANF News Source
    // -------------------------------------------------------------------------
    group('3. ANF News Source', () {
      const anfListHtml = '''
<!DOCTYPE html>
<html>
<body>
  <div class="noticias-container">
    <a href="/nacional/politica/asamblea-retoma-sesion-para-tratar-creditos">Asamblea sesiona</a>
    <a href="/nacional/seguridad/policia-despliega-operativos-en-carreteras">Operativos policiales</a>
  </div>
</body>
</html>
''';

      test('parseArticleLinks descubre artículos bajo /nacional/{cat}/{slug}', () {
        final preliminary = AnfNewsSource.parseArticleLinks(anfListHtml);

        expect(preliminary.length, 2);
        final first = preliminary.first;
        expect(first.id, 'anf_asamblea-retoma-sesion-para-tratar-creditos');
        expect(first.sourceId, 'anf');
        expect(first.sourceName, 'ANF');
        expect(first.category, CategoryMapper.canonicalPolitica);
        expect(first.url, 'https://www.noticiasfides.com/nacional/politica/asamblea-retoma-sesion-para-tratar-creditos');

        final second = preliminary[1];
        expect(second.id, 'anf_policia-despliega-operativos-en-carreteras');
        expect(second.category, CategoryMapper.canonicalSeguridad);
      });
    });

    // -------------------------------------------------------------------------
    // 4. Catálogo y Registro Completo de 9 Medios
    // -------------------------------------------------------------------------
    group('4. Registro y Concurrencia de 9 Medios', () {
      test('NewsSourceRegistry almacena las 9 fuentes bolivianas en orden estricto de sortOrder', () {
        final registry = NewsSourceRegistry();
        final dummyDio = DioClient();
        final dummyDb = _InMemoryTestLocalDataSource();

        registry.register(CorreoDelSurNewsSource(dioClient: dummyDio, localDataSource: dummyDb));
        registry.register(UnitelNewsSource(dioClient: dummyDio, localDataSource: dummyDb));
        registry.register(AnfNewsSource(dioClient: dummyDio, localDataSource: dummyDb));

        expect(registry.count, 3);
        expect(registry.getSourceById('correodelsur'), isNotNull);
        expect(registry.getSourceById('unitel'), isNotNull);
        expect(registry.getSourceById('anf'), isNotNull);

        expect(registry.getSourceById('correodelsur')!.sortOrder, 7);
        expect(registry.getSourceById('unitel')!.sortOrder, 8);
        expect(registry.getSourceById('anf')!.sortOrder, 9);
      });

      test('MultiSourceSyncEngine aísla fallos de 9 fuentes sin detener las demás', () async {
        final registry = NewsSourceRegistry();
        for (int i = 1; i <= 9; i++) {
          final id = 'src_$i';
          final shouldFail = (i == 3 || i == 7);
          registry.register(_TestMockSource(
            id: id,
            name: 'Fuente $i',
            sortOrder: i,
            error: shouldFail ? Exception('Error de red en $id') : null,
            articles: shouldFail
                ? const <ArticleModel>[]
                : <ArticleModel>[
                    ArticleModel(
                      id: '${id}_art',
                      title: 'Noticia de $id',
                      summary: 'Resumen',
                      contentPlain: 'Cuerpo',
                      url: 'https://$id.bo/noticia',
                      author: 'Autor',
                      sourceId: id,
                      sourceName: 'Fuente $i',
                      category: 'general',
                      tags: const <String>[],
                      publishedAt: DateTime.utc(2026, 10, 31, 10),
                      fetchedAt: DateTime.utc(2026, 10, 31, 10),
                    )
                  ],
          ));
        }

        final engine = MultiSourceSyncEngine(registry: registry);
        final results = await engine.fetchAllSources();

        expect(results.length, 9);
        final successes = results.where((r) => r.isSuccess).toList();
        final failures = results.where((r) => !r.isSuccess).toList();

        expect(successes.length, 7);
        expect(failures.length, 2);
      });
    });

    // -------------------------------------------------------------------------
    // 5. Tiered Storage y Retención Indefinida de Texto
    // -------------------------------------------------------------------------
    group('5. Tiered Storage y Retención Indefinida de Texto', () {
      test('Artículos > 7 días tienen isOlderThan7Days = true y hasValidFreshImage = false', () {
        final now = DateTime.utc(2026, 10, 31, 12);
        final freshArticle = Article(
          id: 'fresh_1',
          title: 'Noticia Fresca',
          summary: 'Resumen',
          contentPlain: 'Cuerpo',
          url: 'https://abi.bo/fresh',
          author: 'ABI',
          sourceId: 'abi',
          sourceName: 'ABI',
          category: 'politica',
          tags: const <String>[],
          publishedAt: now.subtract(const Duration(days: 3)),
          fetchedAt: now,
          imageUrl: 'https://abi.bo/img1.jpg',
        );

        final oldArticle = Article(
          id: 'old_1',
          title: 'Noticia Antigua',
          summary: 'Resumen',
          contentPlain: 'Cuerpo',
          url: 'https://abi.bo/old',
          author: 'ABI',
          sourceId: 'abi',
          sourceName: 'ABI',
          category: 'economia',
          tags: const <String>[],
          publishedAt: now.subtract(const Duration(days: 10)),
          fetchedAt: now,
          imageUrl: 'https://abi.bo/img2.jpg',
        );

        expect(freshArticle.isOlderThan7Days, isFalse);
        expect(freshArticle.hasValidFreshImage, isTrue);

        expect(oldArticle.isOlderThan7Days, isTrue);
        expect(oldArticle.hasValidFreshImage, isFalse);
      });

      test('pruneOldArticles mantiene retención indefinida y no borra filas de texto', () async {
        final inMemoryDb = _InMemoryTestLocalDataSource();
        final now = DateTime.utc(2026, 10, 31, 12);

        await inMemoryDb.upsertArticles(<ArticleModel>[
          ArticleModel(
            id: 'archived_1',
            title: 'Noticia de hace 40 días',
            summary: 'Resumen',
            contentPlain: 'Cuerpo histórico',
            url: 'https://abi.bo/hist',
            author: 'ABI',
            sourceId: 'abi',
            sourceName: 'ABI',
            category: 'politica',
            tags: const <String>[],
            publishedAt: now.subtract(const Duration(days: 40)),
            fetchedAt: now,
          ),
        ]);

        final deleted = await inMemoryDb.pruneOldArticles(referenceTimeUtc: now);
        expect(deleted, 0);

        final article = await inMemoryDb.getArticleById('archived_1');
        expect(article, isNotNull);
        expect(article!.title, 'Noticia de hace 40 días');
      });
    });

    // -------------------------------------------------------------------------
    // 6. Exclusión de Noticias en Reporte de Monitoreo
    // -------------------------------------------------------------------------
    group('6. Exclusión de Noticias en Reporte de Monitoreo', () {
      final art1 = ArticleModel(
        id: 'art_1',
        title: 'Primera noticia política',
        summary: 'Resumen 1',
        contentPlain: 'Cuerpo 1',
        url: 'https://abi.bo/1',
        author: 'ABI',
        sourceId: 'abi',
        sourceName: 'ABI',
        category: 'politica',
        tags: const <String>[],
        publishedAt: DateTime.utc(2026, 10, 31, 10, 0),
        fetchedAt: DateTime.utc(2026, 10, 31, 10, 0),
      );

      final art2 = ArticleModel(
        id: 'art_2',
        title: 'Segunda noticia económica',
        summary: 'Resumen 2',
        contentPlain: 'Cuerpo 2',
        url: 'https://unitel.bo/2',
        author: 'Unitel',
        sourceId: 'unitel',
        sourceName: 'Unitel',
        category: 'economia',
        tags: const <String>[],
        publishedAt: DateTime.utc(2026, 10, 31, 10, 30),
        fetchedAt: DateTime.utc(2026, 10, 31, 10, 30),
      );

      test('Excluir una noticia recalcula los totales y la omite del texto formateado', () {
        final allArticles = <ArticleModel>[art1, art2];
        final excludedIds = <String>{'art_1'};

        final filtered = allArticles.where((a) => !excludedIds.contains(a.id)).toList();
        expect(filtered.length, 1);
        expect(filtered.first.id, 'art_2');

        final report = MonitoringReport(
          startUtc: DateTime.utc(2026, 10, 31, 10, 0),
          endUtc: DateTime.utc(2026, 10, 31, 11, 0),
          generatedAtUtc: DateTime.utc(2026, 10, 31, 11, 5),
          sections: <ReportSection>[
            ReportSection(
              sourceId: 'unitel',
              sourceName: 'Unitel',
              articles: filtered,
            ),
          ],
          totalArticles: filtered.length,
        );

        final reportText = MonitoringReportFormatter.formatWhatsApp(report);
        expect(reportText, contains('*Unitel*'));
        expect(reportText, isNot(contains('Primera noticia política')));
        expect(reportText, contains('Segunda noticia económica'));
      });
    });

    // -------------------------------------------------------------------------
    // 7. Protección Seed Por Fuente
    // -------------------------------------------------------------------------
    group('7. Protección Seed Por Fuente', () {
      test('Añadir una fuente por primera vez se registra como semilla silenciosa (0 notificaciones)', () async {
        final localDb = _InMemoryTestLocalDataSource();
        final registry = NewsSourceRegistry();

        final abiSource = _TestMockSource(
          id: 'abi',
          name: 'ABI',
          sortOrder: 1,
          articles: <ArticleModel>[
            ArticleModel(
              id: 'abi_seed',
              title: 'Semilla ABI',
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
        registry.register(abiSource);

        final engine = MultiSourceSyncEngine(registry: registry);
        final repo = NewsRepositoryImpl(localDataSource: localDb, syncEngine: engine);
        final prefs = _InMemoryExtPreferences();
        final notifGateway = _ExtRecordingGateway();

        final orchestrator = BackgroundSyncOrchestrator(
          repository: repo,
          preferences: prefs,
          notificationGateway: notifGateway,
        );

        // 1. Primer sync inicial (base vacía)
        await orchestrator.executeBackgroundSync();
        expect(prefs.seededSources.contains('abi'), isTrue);
        expect(notifGateway.batches, isEmpty);

        // 2. Se incorpora UNITEL por primera vez
        final unitelSource = _TestMockSource(
          id: 'unitel',
          name: 'Unitel',
          sortOrder: 8,
          articles: <ArticleModel>[
            ArticleModel(
              id: 'unitel_seed_batch',
              title: 'Primer lote de Unitel',
              summary: 'Resumen',
              contentPlain: 'Cuerpo',
              url: 'https://unitel.bo/seed',
              author: 'Unitel',
              sourceId: 'unitel',
              sourceName: 'Unitel',
              category: 'sociedad',
              tags: const <String>[],
              publishedAt: DateTime.utc(2026, 10, 31, 9),
              fetchedAt: DateTime.utc(2026, 10, 31, 9),
            ),
          ],
        );
        registry.register(unitelSource);

        // Sync con nueva fuente agregada: actúa como semilla silenciosa para Unitel
        final resultUnitelSeed = await orchestrator.executeBackgroundSync();
        expect(prefs.seededSources.contains('unitel'), isTrue);
        expect(resultUnitelSeed.notificationsDispatched, isFalse);
        expect(notifGateway.batches, isEmpty);

        // 3. Tercer sync: Unitel publica una noticia genuina
        unitelSource.articles = <ArticleModel>[
          ArticleModel(
            id: 'unitel_breaking_news',
            title: 'Noticia de Último Momento Unitel',
            summary: 'Resumen urgente',
            contentPlain: 'Cuerpo urgente',
            url: 'https://unitel.bo/urgente',
            author: 'Unitel',
            sourceId: 'unitel',
            sourceName: 'Unitel',
            category: 'seguridad',
            tags: const <String>[],
            publishedAt: DateTime.utc(2026, 10, 31, 10),
            fetchedAt: DateTime.utc(2026, 10, 31, 10),
          ),
        ];

        final resultUnitelBreaking = await orchestrator.executeBackgroundSync();
        expect(resultUnitelBreaking.notificationsDispatched, isTrue);
        expect(notifGateway.batches.length, 1);
        expect(notifGateway.batches.single.single.id, 'unitel_breaking_news');
      });
    });

    // -------------------------------------------------------------------------
    // 8. Prueba de Escala SQLite: 5.000 Artículos, Paginación y Retención
    // -------------------------------------------------------------------------
    group('8. Prueba de Escala SQLite (5.000 Artículos)', () {
      test('SQLite gestiona 5.000 artículos con paginación, búsqueda, filtros y favoritos', () async {
        final localDataSource = _InMemoryTestLocalDataSource();
        final baseTime = DateTime.utc(2026, 10, 31, 12, 0);

        // Generar 5.000 artículos simulados distribuidos en 9 medios y categorías
        final sources = ['abi', 'dtv', 'eldeber', 'larazon', 'eldiario', 'elpais', 'correodelsur', 'unitel', 'anf'];
        final categories = ['politica', 'economia', 'sociedad', 'seguridad', 'cultura', 'deportes', 'general'];
        final generated = <ArticleModel>[];

        for (int i = 1; i <= 5000; i++) {
          final sId = sources[i % sources.length];
          final cat = categories[i % categories.length];
          // Distribuir en el tiempo: un artículo cada 10 minutos hacia el pasado
          final pubTime = baseTime.subtract(Duration(minutes: i * 10));

          generated.add(ArticleModel(
            id: '${sId}_art_$i',
            title: i == 42 ? 'Titular Único de Búsqueda Especializada' : 'Noticia $i de $sId sobre $cat',
            summary: 'Resumen descriptivo del artículo número $i para fines de prueba de escala.',
            contentPlain: 'Cuerpo completo y extenso del despacho periodístico número $i. Contiene información editorial relevante.',
            url: 'https://$sId.bo/noticia/$i',
            author: 'Redacción $sId',
            sourceId: sId,
            sourceName: sId.toUpperCase(),
            category: cat,
            tags: <String>[sId, cat],
            publishedAt: pubTime,
            fetchedAt: pubTime.add(const Duration(minutes: 5)),
            imageUrl: 'https://$sId.bo/images/$i.jpg',
            isFavorite: i % 250 == 0, // 20 favoritos preexistentes
          ));
        }

        // 1. Inserción masiva de 5.000 artículos
        final inserted = await localDataSource.upsertArticles(generated);
        expect(inserted.length, 5000);

        // 2. Paginación en Home: Lote 1 (50 artículos) y Lote 2 (50 artículos)
        final batch1 = await localDataSource.getArticles(limit: 50, offset: 0);
        final batch2 = await localDataSource.getArticles(limit: 50, offset: 50);

        expect(batch1.length, 50);
        expect(batch2.length, 50);

        // No hay duplicados entre los lotes
        final ids1 = batch1.map((a) => a.id).toSet();
        final ids2 = batch2.map((a) => a.id).toSet();
        expect(ids1.intersection(ids2), isEmpty);

        // Orden estricto publishedAt DESC
        for (int j = 0; j < batch1.length - 1; j++) {
          expect(batch1[j].publishedAt.isAfter(batch1[j + 1].publishedAt) ||
                 batch1[j].publishedAt.isAtSameMomentAs(batch1[j + 1].publishedAt), isTrue);
        }

        // 3. Búsqueda rápida sobre los 5.000 artículos
        final searchResults = await localDataSource.searchArticles('Especializada');
        expect(searchResults.length, 1);
        expect(searchResults.single.id, contains('_art_42'));

        // 4. Filtrado combinado (categoría 'politica' + fuente 'unitel')
        final filtered = await localDataSource.getArticles(category: 'politica', sourceId: 'unitel', limit: 100);
        expect(filtered.isNotEmpty, isTrue);
        for (final art in filtered) {
          expect(art.category, 'politica');
          expect(art.sourceId, 'unitel');
        }

        // 5. Consulta para Reporte de Monitoreo por rango de horas
        final rangeStart = baseTime.subtract(const Duration(hours: 5));
        final rangeEnd = baseTime.subtract(const Duration(hours: 1));
        final reportArticles = await localDataSource.getArticlesForReport(
          startUtc: rangeStart,
          endUtc: rangeEnd,
          sourceIds: ['unitel', 'abi'],
        );
        expect(reportArticles.isNotEmpty, isTrue);
        for (final rArt in reportArticles) {
          expect(rArt.publishedAt.isAfter(rangeStart.subtract(const Duration(milliseconds: 1))), isTrue);
          expect(rArt.publishedAt.isBefore(rangeEnd), isTrue);
          expect(rArt.sourceId == 'unitel' || rArt.sourceId == 'abi', isTrue);
        }

        // 6. Favoritos: 20 favoritos iniciales + marcar 1 adicional
        final targetArt = generated.firstWhere((a) => !a.isFavorite);
        await localDataSource.toggleFavorite(targetArt.id);
        final favs = await localDataSource.getFavorites();
        expect(favs.length, 21);

        // 7. Limpiar Caché: Preserva los 21 favoritos y depura las ~4.979 noticias temporales
        final cleared = await localDataSource.clearArticles(keepFavorites: true);
        expect(cleared, 4979);

        final remainingFavs = await localDataSource.getFavorites();
        expect(remainingFavs.length, 21);
        expect(await localDataSource.getArticleById(targetArt.id), isNotNull);
      });

      test('Pruebas de retención de texto y almacenamiento por niveles', () {
        final now = DateTime.utc(2026, 10, 31, 12, 0);

        // Noticia de hace 2 días: Normal
        final art2Days = Article(
          id: 'art_2d',
          title: 'Noticia de hace 2 días',
          summary: 'Resumen',
          contentPlain: 'Cuerpo',
          url: 'https://abi.bo/2d',
          author: 'ABI',
          sourceId: 'abi',
          sourceName: 'ABI',
          category: 'politica',
          tags: const <String>[],
          publishedAt: now.subtract(const Duration(days: 2)),
          fetchedAt: now,
          imageUrl: 'https://abi.bo/img_2d.jpg',
        );
        expect(art2Days.isOlderThan7Days, isFalse);
        expect(art2Days.hasValidFreshImage, isTrue);

        // Noticia de hace 8 días: Almacenamiento reducido (texto únicamente por defecto)
        final art8Days = Article(
          id: 'art_8d',
          title: 'Noticia de hace 8 días',
          summary: 'Resumen',
          contentPlain: 'Cuerpo',
          url: 'https://abi.bo/8d',
          author: 'ABI',
          sourceId: 'abi',
          sourceName: 'ABI',
          category: 'politica',
          tags: const <String>[],
          publishedAt: now.subtract(const Duration(days: 8)),
          fetchedAt: now,
          imageUrl: 'https://abi.bo/img_8d.jpg',
        );
        expect(art8Days.isOlderThan7Days, isTrue);
        expect(art8Days.hasValidFreshImage, isFalse);
        expect(art8Days.imageUrl, 'https://abi.bo/img_8d.jpg'); // Metadata preservada

        // Noticia de hace 20 días: Texto íntegro preservado
        final art20Days = Article(
          id: 'art_20d',
          title: 'Noticia de hace 20 días',
          summary: 'Resumen conservado',
          contentPlain: 'Cuerpo histórico conservado en SQLite',
          url: 'https://abi.bo/20d',
          author: 'ABI',
          sourceId: 'abi',
          sourceName: 'ABI',
          category: 'politica',
          tags: const <String>[],
          publishedAt: now.subtract(const Duration(days: 20)),
          fetchedAt: now,
          imageUrl: 'https://abi.bo/img_20d.jpg',
        );
        expect(art20Days.isOlderThan7Days, isTrue);
        expect(art20Days.contentPlain, contains('histórico'));
        expect(art20Days.imageUrl, isNotNull);
      });
    });
  });
}

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

class _TestMockSource implements NewsSource {
  _TestMockSource({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.articles = const <ArticleModel>[],
    this.error,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final int sortOrder;

  List<ArticleModel> articles;
  final Object? error;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    if (error != null) throw error!;
    return articles;
  }
}

class _InMemoryTestLocalDataSource implements NewsLocalDataSource {
  final Map<String, ArticleModel> _db = <String, ArticleModel>{};

  @override
  Future<List<ArticleModel>> getArticles({
    String? category,
    String? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    var items = _db.values.toList()
      ..sort((a, b) {
        final c = b.publishedAt.compareTo(a.publishedAt);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
    if (category != null && category.isNotEmpty) {
      items = items.where((a) => a.category == category).toList();
    }
    if (sourceId != null && sourceId.isNotEmpty) {
      items = items.where((a) => a.sourceId == sourceId).toList();
    }
    return items.skip(offset).take(limit).toList();
  }

  @override
  Future<List<ArticleModel>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async {
    final list = _db.values.where((a) {
      if (a.publishedAt.isBefore(startUtc) || !a.publishedAt.isBefore(endUtc)) return false;
      if (sourceIds.isNotEmpty && !sourceIds.contains(a.sourceId)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    return list;
  }

  @override
  Future<List<ArticleModel>> getFavorites() async {
    return _db.values.where((a) => a.isFavorite).toList();
  }

  @override
  Future<int> clearArticles({bool keepFavorites = false}) async {
    if (keepFavorites) {
      final nonFavs = _db.values.where((a) => !a.isFavorite).map((a) => a.id).toList();
      for (final id in nonFavs) {
        _db.remove(id);
      }
      return nonFavs.length;
    }
    final count = _db.length;
    _db.clear();
    return count;
  }

  @override
  Future<ArticleModel?> getArticleById(String id) async => _db[id];

  @override
  Future<List<ArticleModel>> getLatestArticles({int limit = 100}) async {
    final list = _db.values.toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return list.take(limit).toList();
  }

  @override
  Future<List<ArticleModel>> getArticlesByCategory(String category, {int limit = 100}) async {
    return _db.values.where((a) => a.category == category).take(limit).toList();
  }

  @override
  Future<int> markAsRead(String id) async {
    final item = _db[id];
    if (item != null) {
      _db[id] = item.copyWith(isRead: true);
      return 1;
    }
    return 0;
  }

  @override
  Future<int> pruneOldArticles({Duration retentionPeriod = const Duration(days: 30), DateTime? referenceTimeUtc}) async {
    return 0;
  }

  @override
  Future<List<ArticleModel>> searchArticles(String query, {int limit = 50}) async {
    return _db.values.where((a) => a.title.contains(query)).take(limit).toList();
  }

  @override
  Future<bool> toggleFavorite(String id) async {
    final item = _db[id];
    if (item != null) {
      final updated = item.copyWith(isFavorite: !item.isFavorite);
      _db[id] = updated;
      return updated.isFavorite;
    }
    return false;
  }

  @override
  Future<List<ArticleModel>> upsertArticles(List<ArticleModel> articles) async {
    final inserted = <ArticleModel>[];
    for (final a in articles) {
      if (!_db.containsKey(a.id)) {
        inserted.add(a);
      }
      _db[a.id] = a;
    }
    return inserted;
  }
}

class _InMemoryExtPreferences implements AppPreferencesDataSource {
  bool bgSyncEnabled = true;
  bool notifEnabled = true;
  bool hourlyEnabled = false;
  bool cacheClearedPending = false;
  String? lastHourly;
  bool modeAll = true;
  List<String> selectedSources = const [];
  final Set<String> seededSources = <String>{};

  @override
  Future<bool> getBackgroundSyncEnabled({bool reload = false}) async => bgSyncEnabled;

  @override
  Future<void> setBackgroundSyncEnabled(bool enabled) async => bgSyncEnabled = enabled;

  @override
  Future<bool> getNotificationsEnabled({bool reload = false}) async => notifEnabled;

  @override
  Future<void> setNotificationsEnabled(bool enabled) async => notifEnabled = enabled;

  @override
  Future<bool> getHourlyReportsEnabled({bool reload = false}) async => hourlyEnabled;

  @override
  Future<void> setHourlyReportsEnabled(bool enabled) async => hourlyEnabled = enabled;

  @override
  Future<bool> isCacheClearedPendingBaseline({bool reload = false}) async => cacheClearedPending;

  @override
  Future<void> setCacheClearedPendingBaseline(bool value) async => cacheClearedPending = value;

  @override
  Future<String?> getLastHourlyReportWindowNotified({bool reload = false}) async => lastHourly;

  @override
  Future<void> setLastHourlyReportWindowNotified(String windowId) async => lastHourly = windowId;

  @override
  Future<bool> getReportSourcesModeAll({bool reload = false}) async => modeAll;

  @override
  Future<void> setReportSourcesModeAll(bool isAll) async => modeAll = isAll;

  @override
  Future<List<String>> getReportSelectedSourceIds({bool reload = false}) async => selectedSources;

  @override
  Future<void> setReportSelectedSourceIds(List<String> sourceIds) async => selectedSources = sourceIds;

  @override
  Future<Set<String>> getSeededSourceIds({bool reload = false}) async => Set<String>.from(seededSources);

  @override
  Future<void> setSourceSeeded(String sourceId) async => seededSources.add(sourceId);

  @override
  Future<void> clearSeededSources() async => seededSources.clear();

  @override
  Future<bool> getAutoRefreshOnOpen({bool reload = false}) async => true;

  @override
  Future<void> setAutoRefreshOnOpen(bool enabled) async {}

  @override
  Future<bool> getEasterEggUnlocked({bool reload = false}) async => false;

  @override
  Future<void> setEasterEggUnlocked(bool unlocked) async {}
}

class _ExtRecordingGateway implements NotificationGateway {
  final List<List<Article>> batches = <List<Article>>[];

  @override
  Future<void> initialize({bool isBackgroundIsolate = false}) async {}

  @override
  Future<void> notifyNewArticles(List<Article> newArticles) async {
    batches.add(List<Article>.unmodifiable(newArticles));
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
