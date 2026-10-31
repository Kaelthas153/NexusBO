import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/domain/entities/sync_result.dart';
import 'package:nexusbo/features/news/domain/repositories/news_repository.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';
import 'package:nexusbo/features/reports/domain/models/monitoring_report.dart';
import 'package:nexusbo/features/reports/domain/services/monitoring_report_formatter.dart';
import 'package:nexusbo/features/reports/domain/services/monitoring_report_service.dart';
import 'package:nexusbo/services/background/background_task_service.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';
import 'package:nexusbo/services/preferences/app_preferences_service.dart';

void main() {
  group('Etapa 8: Módulo de Monitoreo y Reportes por Rango Horario', () {
    // -------------------------------------------------------------------------
    // 1. LÍMITES TEMPORALES Y HORA DE BOLIVIA (UTC-4)
    // -------------------------------------------------------------------------
    group('1. Límites y conversiones de hora de Bolivia (UTC-4)', () {
      test('Límites inclusivo [start] y exclusivo [end): 07:59 NO, 08:00 SÍ, 08:30 SÍ, 08:59:59 SÍ, 09:00 NO',
          () async {
        final localDataSource = _InMemoryNewsLocalDataSource();

        // 08:00 BOT equivale a 12:00 UTC (Bolivia = UTC-4)
        final startUtc = DateTime.utc(2026, 10, 31, 12, 0, 0);
        final endUtc = DateTime.utc(2026, 10, 31, 13, 0, 0);

        // Artículos de prueba con diferentes marcas de tiempo
        final a0759 = _buildArticle(
          id: 'art_0759',
          title: 'Antes del rango',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 11, 59, 59, 999),
          sourceId: 'abi',
        );
        final a0800 = _buildArticle(
          id: 'art_0800',
          title: 'Exactamente al inicio',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 0, 0, 0),
          sourceId: 'abi',
        );
        final a0830 = _buildArticle(
          id: 'art_0830',
          title: 'A mitad de hora',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 30, 0, 0),
          sourceId: 'abi',
        );
        final a0859 = _buildArticle(
          id: 'art_0859',
          title: 'Último milisegundo dentro',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 59, 59, 999),
          sourceId: 'abi',
        );
        final a0900 = _buildArticle(
          id: 'art_0900',
          title: 'Exactamente al final (excluido)',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 13, 0, 0, 0),
          sourceId: 'abi',
        );

        await localDataSource.upsertArticles([a0759, a0800, a0830, a0859, a0900]);

        final results = await localDataSource.getArticlesForReport(
          startUtc: startUtc,
          endUtc: endUtc,
          sourceIds: ['abi'],
        );

        final resultIds = results.map((a) => a.id).toList();
        expect(resultIds.contains('art_0759'), isFalse, reason: '07:59 debe quedar excluido');
        expect(resultIds.contains('art_0800'), isTrue, reason: '08:00 exacto debe ser incluido');
        expect(resultIds.contains('art_0830'), isTrue, reason: '08:30 debe ser incluido');
        expect(resultIds.contains('art_0859'), isTrue, reason: '08:59:59.999 debe ser incluido');
        expect(resultIds.contains('art_0900'), isFalse, reason: '09:00 exacto debe quedar excluido');
        expect(resultIds.length, 3);
      });

      test('Cálculo determinista de última hora completa en hora de Bolivia', () {
        // Caso 1: 10:53 BOT (14:53 UTC) -> Ventana: 09:00 a 10:00 BOT (13:00 a 14:00 UTC)
        final ref1Utc = DateTime.utc(2026, 10, 31, 14, 53, 20);
        final win1 = MonitoringReportService.calculateLastCompleteHourWindow(
          referenceUtc: ref1Utc,
        );
        expect(win1.startBolivia.hour, 9);
        expect(win1.startBolivia.minute, 0);
        expect(win1.endBolivia.hour, 10);
        expect(win1.endBolivia.minute, 0);
        expect(win1.startUtc, DateTime.utc(2026, 10, 31, 13, 0, 0));
        expect(win1.endUtc, DateTime.utc(2026, 10, 31, 14, 0, 0));

        // Caso 2: 09:03 BOT (13:03 UTC) -> Ventana: 08:00 a 09:00 BOT (12:00 a 13:00 UTC)
        final ref2Utc = DateTime.utc(2026, 10, 31, 13, 3, 0);
        final win2 = MonitoringReportService.calculateLastCompleteHourWindow(
          referenceUtc: ref2Utc,
        );
        expect(win2.startBolivia.hour, 8);
        expect(win2.endBolivia.hour, 9);

        // Caso 3: Transición de medianoche: 00:15 BOT del 31/10 (04:15 UTC) -> Ventana: 23:00 del 30/10 a 00:00 del 31/10
        final ref3Utc = DateTime.utc(2026, 10, 31, 4, 15, 0);
        final win3 = MonitoringReportService.calculateLastCompleteHourWindow(
          referenceUtc: ref3Utc,
        );
        expect(win3.startBolivia.day, 30);
        expect(win3.startBolivia.hour, 23);
        expect(win3.endBolivia.day, 31);
        expect(win3.endBolivia.hour, 0);
        expect(win3.startUtc, DateTime.utc(2026, 10, 31, 3, 0, 0));
        expect(win3.endUtc, DateTime.utc(2026, 10, 31, 4, 0, 0));
      });

      test('isRecentRange detecta correctamente si el rango está dentro de las últimas 24h', () {
        final nowUtc = DateTime.utc(2026, 10, 31, 15, 0, 0);

        // Hace 2 horas: reciente
        final recentStart = nowUtc.subtract(const Duration(hours: 3));
        final recentEnd = nowUtc.subtract(const Duration(hours: 2));
        expect(MonitoringReportService.isRecentRange(recentStart, recentEnd, nowUtc: nowUtc), isTrue);

        // Hace 3 días: histórico (no reciente)
        final pastStart = nowUtc.subtract(const Duration(days: 3));
        final pastEnd = nowUtc.subtract(const Duration(days: 3, hours: -1));
        expect(MonitoringReportService.isRecentRange(pastStart, pastEnd, nowUtc: nowUtc), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 2. OFFLINE-FIRST, REPOSITORIO Y SINCRONIZACIÓN SELECTIVA
    // -------------------------------------------------------------------------
    group('2. Offline-First SQLite y Single Source of Truth', () {
      test('syncSelectedSources sincroniza fuentes seleccionadas y hace UPSERT incremental', () async {
        final localDataSource = _InMemoryNewsLocalDataSource();
        final mockSource1 = _MockNewsSource('abi', 'ABI', [
          _buildArticle(
            id: 'abi_1',
            title: 'Noticia 1 ABI',
            publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 10),
            sourceId: 'abi',
          ),
        ]);
        final mockSource2 = _MockNewsSource('dtv', 'DTV', [
          _buildArticle(
            id: 'dtv_1',
            title: 'Noticia 1 DTV',
            publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 20),
            sourceId: 'dtv',
          ),
        ]);

        final registry = NewsSourceRegistry(initialSources: [mockSource1, mockSource2]);
        final repository = _FakeTestNewsRepository(
          localDataSource: localDataSource,
          registry: registry,
        );

        // Sincronizar solo ABI
        final syncResult = await repository.syncSelectedSources([mockSource1]);
        expect(syncResult.fetched, 1);
        expect(syncResult.inserted, 1);

        // Consultar SQLite para reporte
        final articles = await repository.getArticlesForReport(
          startUtc: DateTime.utc(2026, 10, 31, 12, 0),
          endUtc: DateTime.utc(2026, 10, 31, 13, 0),
          sourceIds: ['abi', 'dtv'],
        );

        expect(articles.length, 1);
        expect(articles.first.id, 'abi_1');
      });

      test('Fallo de red en una fuente no interrumpe el reporte: SQLite genera reporte con aviso',
          () async {
        final localDataSource = _InMemoryNewsLocalDataSource();
        // Insertar datos previos en SQLite
        await localDataSource.upsertArticles([
          _buildArticle(
            id: 'prev_abi',
            title: 'Noticia histórica ABI',
            publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 15),
            sourceId: 'abi',
          ),
        ]);

        final failingSource = _MockFailingNewsSource('eldeber', 'El Deber');
        final registry = NewsSourceRegistry(initialSources: [failingSource]);
        final repository = _FakeTestNewsRepository(
          localDataSource: localDataSource,
          registry: registry,
        );

        final syncResult = await repository.syncSelectedSources([failingSource]);
        expect(syncResult.warning, contains('El Deber'));

        // El reporte se construye desde SQLite con los datos existentes
        final articles = await repository.getArticlesForReport(
          startUtc: DateTime.utc(2026, 10, 31, 12, 0),
          endUtc: DateTime.utc(2026, 10, 31, 13, 0),
          sourceIds: ['abi', 'eldeber'],
        );

        expect(articles.length, 1);
        expect(articles.first.id, 'prev_abi');
      });
    });

    // -------------------------------------------------------------------------
    // 3. AGRUPACIÓN POR MEDIO Y ORDEN CRONOLÓGICO ASCENDENTE
    // -------------------------------------------------------------------------
    group('3. Agrupación y orden cronológico en MonitoringReport', () {
      test('Agrupa respetando el orden del NewsSourceRegistry y ordena artículos por publishedAt ASC',
          () {
        final sourceAbi = _MockNewsSource('abi', 'ABI', []);
        final sourceDtv = _MockNewsSource('dtv', 'DTV', []);
        final sourceElDeber = _MockNewsSource('eldeber', 'El Deber', []);
        final orderedSources = [sourceAbi, sourceDtv, sourceElDeber];

        // Artículos con horas desordenadas
        final articles = <ArticleModel>[
          _buildArticle(
            id: 'eldeber_1',
            title: 'El Deber 08:45',
            publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 45),
            sourceId: 'eldeber',
          ),
          _buildArticle(
            id: 'abi_2',
            title: 'ABI 08:30',
            publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 30),
            sourceId: 'abi',
          ),
          _buildArticle(
            id: 'abi_1',
            title: 'ABI 08:05',
            publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 5),
            sourceId: 'abi',
          ),
        ];

        final report = MonitoringReportService.buildReport(
          startUtc: DateTime.utc(2026, 10, 31, 12, 0),
          endUtc: DateTime.utc(2026, 10, 31, 13, 0),
          articles: articles,
          orderedSources: orderedSources,
        );

        expect(report.totalArticles, 3);
        expect(report.sections.length, 2, reason: 'DTV no tuvo noticias, debe omitirse');

        // Primera sección: ABI (según registro)
        expect(report.sections[0].sourceId, 'abi');
        expect(report.sections[0].articles.length, 2);
        expect(report.sections[0].articles[0].id, 'abi_1', reason: '08:05 debe ir antes que 08:30 (ASC)');
        expect(report.sections[0].articles[1].id, 'abi_2');

        // Segunda sección: El Deber
        expect(report.sections[1].sourceId, 'eldeber');
        expect(report.sections[1].articles.length, 1);
      });
    });

    // -------------------------------------------------------------------------
    // 4. FORMATEO PARA WHATSAPP
    // -------------------------------------------------------------------------
    group('4. Formateador de WhatsApp (MonitoringReportFormatter)', () {
      test('Formatea correctamente encabezado, negritas asterisco (*), resumen limpio y enlace',
          () {
        final startUtc = DateTime.utc(2026, 10, 31, 12, 0); // 08:00 BOT
        final endUtc = DateTime.utc(2026, 10, 31, 13, 0);   // 09:00 BOT

        final articleAbi = _buildArticle(
          id: 'abi_1',
          title: 'Presidente entrega represa en Cochabamba',
          summary: 'La obra beneficiará a más de cinco mil familias de regantes de la zona.',
          url: 'https://abi.bo/noticia-1',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 15),
          sourceId: 'abi',
        );

        final section = ReportSection(
          sourceId: 'abi',
          sourceName: 'ABI',
          articles: [articleAbi],
        );

        final report = MonitoringReport(
          startUtc: startUtc,
          endUtc: endUtc,
          sections: [section],
          totalArticles: 1,
          generatedAtUtc: DateTime.utc(2026, 10, 31, 13, 5),
        );

        final formatted = MonitoringReportFormatter.formatWhatsApp(report);

        // Verifica negritas asterisco obligatorias en WhatsApp
        expect(formatted, contains('*MONITOREO 31/10/2026 08:00 am - 09:00 am*'));
        expect(formatted, contains('*ABI*'));

        // Verifica titular precedido por viñeta guion
        expect(formatted, contains('- Presidente entrega represa en Cochabamba'));

        // Verifica resumen limpio
        expect(formatted, contains('La obra beneficiará a más de cinco mil familias'));

        // Verifica enlace sin escapar
        expect(formatted, contains('https://abi.bo/noticia-1'));
      });

      test('extractCleanSummary corta limpiamente por signo de puntuación y evita títulos duplicados',
          () {
        const longText =
            'La Agencia Boliviana de Información reportó nuevos avances en la construcción de carreteras interdepartamentales. '
            'Este proyecto contempla más de doscientos kilómetros de asfalto flexible y puentes de hormigón armado. '
            'Las autoridades locales expresaron su satisfacción por el cumplimiento de los cronogramas establecidos.';

        final art = _buildArticle(
          id: 'test_sum_1',
          title: 'Reportan avances en carreteras',
          summary: longText,
          publishedAtUtc: DateTime.utc(2026, 10, 31, 12, 0),
          sourceId: 'abi',
        );

        final summary = MonitoringReportFormatter.extractCleanSummary(art);

        expect(summary.length, lessThanOrEqualTo(350));
        // Debe terminar en punto o delimitador limpio, no a mitad de palabra
        expect(summary.endsWith('.'), isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 5. NOTIFICACIONES HORARIAS Y ANTI-FLOOD EN WORKMANAGER
    // -------------------------------------------------------------------------
    group('5. Notificaciones de reporte horario y anti-flood', () {
      test('Notificación no se repite para la misma ventana horaria ya notificada', () async {
        final preferences = _InMemoryTestPreferences();
        final localDataSource = _InMemoryNewsLocalDataSource();
        final gateway = _RecordingTestNotificationGateway();

        // 12:00 a 13:00 UTC = 08:00 a 09:00 BOT
        final window = MonitoringReportService.calculateLastCompleteHourWindow(
          referenceUtc: DateTime.utc(2026, 10, 31, 13, 10),
        );

        // Pre-configurar ventana como ya notificada
        await preferences.setLastHourlyReportWindowNotified(window.windowId);

        final repository = _FakeTestNewsRepository(
          localDataSource: localDataSource,
          registry: NewsSourceRegistry(initialSources: []),
        );

        final orchestrator = BackgroundSyncOrchestrator(
          repository: repository,
          preferences: preferences,
          notificationGateway: gateway,
        );

        final dispatched = await orchestrator.triggerHourlyReportCheckNow(
          referenceUtc: DateTime.utc(2026, 10, 31, 13, 10),
          force: false,
        );

        expect(dispatched, isFalse, reason: 'Anti-flood debe bloquear la notificación ya emitida');
        expect(gateway.dispatchedHourlyReports, isEmpty);
      });

      test('Si el usuario desactiva reportes horarios, no se emite notificación pero el sync continúa',
          () async {
        final preferences = _InMemoryTestPreferences();
        await preferences.setHourlyReportsEnabled(false);

        final localDataSource = _InMemoryNewsLocalDataSource();
        final gateway = _RecordingTestNotificationGateway();
        final repository = _FakeTestNewsRepository(
          localDataSource: localDataSource,
          registry: NewsSourceRegistry(initialSources: []),
        );

        final orchestrator = BackgroundSyncOrchestrator(
          repository: repository,
          preferences: preferences,
          notificationGateway: gateway,
        );

        final dispatched = await orchestrator.triggerHourlyReportCheckNow(
          referenceUtc: DateTime.utc(2026, 10, 31, 13, 10),
          force: false,
        );

        expect(dispatched, isFalse);
        expect(gateway.dispatchedHourlyReports, isEmpty);
      });

      test('Multiples horas en suspensión: solo evalúa y notifica la última hora completa real',
          () async {
        final preferences = _InMemoryTestPreferences();
        final localDataSource = _InMemoryNewsLocalDataSource();
        final gateway = _RecordingTestNotificationGateway();

        // Dispositivo suspendido desde las 06:00 y despierta a las 11:20 BOT (15:20 UTC)
        final wakeUtc = DateTime.utc(2026, 10, 31, 15, 20);
        final lastWindow = MonitoringReportService.calculateLastCompleteHourWindow(
          referenceUtc: wakeUtc,
        );

        // La ventana debe ser estrictamente 10:00 a 11:00 BOT (14:00 a 15:00 UTC)
        expect(lastWindow.startBolivia.hour, 10);
        expect(lastWindow.endBolivia.hour, 11);

        final repository = _FakeTestNewsRepository(
          localDataSource: localDataSource,
          registry: NewsSourceRegistry(initialSources: []),
        );

        final orchestrator = BackgroundSyncOrchestrator(
          repository: repository,
          preferences: preferences,
          notificationGateway: gateway,
        );

        final dispatched = await orchestrator.triggerHourlyReportCheckNow(
          referenceUtc: wakeUtc,
          force: false,
        );

        expect(dispatched, isTrue);
        expect(gateway.dispatchedHourlyReports.length, 1);
        expect(gateway.dispatchedHourlyReports.first.windowLabel, contains('10:00 am - 11:00 am'));
      });
    });

    // -------------------------------------------------------------------------
    // 6. CODEC DE PAYLOADS DE NOTIFICACIÓN
    // -------------------------------------------------------------------------
    group('6. Codec de payloads de notificación (AppNotificationPayload)', () {
      test('Decodifica payload de reporte horario con inicio y fin en ms', () {
        const raw = 'report:1730379600000:1730383200000';
        final parsed = AppNotificationPayload.parse(raw);

        expect(parsed, isA<ReportNotificationPayload>());
        final reportPayload = parsed as ReportNotificationPayload;
        expect(reportPayload.startUtc.millisecondsSinceEpoch, 1730379600000);
        expect(reportPayload.endUtc.millisecondsSinceEpoch, 1730383200000);
      });

      test('Decodifica payload de artículo individual', () {
        const raw = 'article:abi_2026_10_31_001';
        final parsed = AppNotificationPayload.parse(raw);

        expect(parsed, isA<ArticleNotificationPayload>());
        final articlePayload = parsed as ArticleNotificationPayload;
        expect(articlePayload.articleId, 'abi_2026_10_31_001');
      });

      test('Fallback seguro a HomeNotificationPayload ante nulos, vacíos o reportes corruptos', () {
        expect(AppNotificationPayload.parse(null), isA<HomeNotificationPayload>());
        expect(AppNotificationPayload.parse(''), isA<HomeNotificationPayload>());
        expect(AppNotificationPayload.parse('home'), isA<HomeNotificationPayload>());
        expect(AppNotificationPayload.parse('nexusbo:home'), isA<HomeNotificationPayload>());
        expect(AppNotificationPayload.parse('report:not_numbers:neither'), isA<HomeNotificationPayload>());
        expect(AppNotificationPayload.parse('report:123'), isA<HomeNotificationPayload>());
      });
    });

    group('8. Exclusión y restauración en vista previa de reportes', () {
      test('ReportsState mantiene excludedArticleIds y regenera reporte sin alterar SQLite', () {
        final a1 = _buildArticle(
          id: 'art_1',
          title: 'Noticia 1',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 10, 0),
          sourceId: 'abi',
        );
        final a2 = _buildArticle(
          id: 'art_2',
          title: 'Noticia 2',
          publishedAtUtc: DateTime.utc(2026, 10, 31, 10, 15),
          sourceId: 'abi',
        );

        final initialReport = MonitoringReportService.buildReport(
          startUtc: DateTime.utc(2026, 10, 31, 10, 0),
          endUtc: DateTime.utc(2026, 10, 31, 11, 0),
          articles: [a1, a2],
          orderedSources: [_MockNewsSource('abi', 'ABI', const [])],
        );

        expect(initialReport.totalArticles, 2);

        // Excluir a1
        final filteredArticles = [a1, a2].where((a) => a.id != 'art_1').toList();
        final reportAfterExclusion = MonitoringReportService.buildReport(
          startUtc: DateTime.utc(2026, 10, 31, 10, 0),
          endUtc: DateTime.utc(2026, 10, 31, 11, 0),
          articles: filteredArticles,
          orderedSources: [_MockNewsSource('abi', 'ABI', const [])],
        );

        expect(reportAfterExclusion.totalArticles, 1);
        expect(reportAfterExclusion.sections.first.articles.first.id, 'art_2');

        // Restaurar a1
        final restoredReport = MonitoringReportService.buildReport(
          startUtc: DateTime.utc(2026, 10, 31, 10, 0),
          endUtc: DateTime.utc(2026, 10, 31, 11, 0),
          articles: [a1, a2],
          orderedSources: [_MockNewsSource('abi', 'ABI', const [])],
        );

        expect(restoredReport.totalArticles, 2);
        expect(restoredReport.sections.first.articles.first.id, 'art_1');
      });
    });
  });
}

// =============================================================================
// HELPERS Y FAKES PARA PRUEBAS DE REPORTE
// =============================================================================

ArticleModel _buildArticle({
  required String id,
  required String title,
  required DateTime publishedAtUtc,
  required String sourceId,
  String summary = 'Resumen editorial de prueba.',
  String url = 'https://ejemplo.bo/noticia',
  String author = 'Redacción',
}) {
  return ArticleModel(
    id: id,
    title: title,
    summary: summary,
    contentPlain: '$summary Más texto en el cuerpo de la noticia para validar la longitud del resumen.',
    url: url,
    author: author,
    sourceId: sourceId,
    sourceName: sourceId.toUpperCase(),
    category: 'politica',
    tags: const <String>['Bolivia'],
    publishedAt: publishedAtUtc,
    fetchedAt: publishedAtUtc.add(const Duration(minutes: 5)),
  );
}

class _InMemoryNewsLocalDataSource implements NewsLocalDataSource {
  final Map<String, ArticleModel> _store = <String, ArticleModel>{};

  @override
  Future<List<ArticleModel>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async {
    final normalized = sourceIds.map((s) => s.toLowerCase()).toSet();
    final items = _store.values.where((article) {
      final pub = article.publishedAt.toUtc();
      final inRange = !pub.isBefore(startUtc) && pub.isBefore(endUtc);
      final inSource = normalized.isEmpty || normalized.contains(article.sourceId.toLowerCase());
      return inRange && inSource;
    }).toList()
      ..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    return items;
  }

  @override
  Future<List<ArticleModel>> upsertArticles(List<ArticleModel> articles) async {
    for (final a in articles) {
      _store[a.id] = a;
    }
    return articles;
  }

  @override
  Future<List<ArticleModel>> getLatestArticles({int limit = 100}) async =>
      _store.values.toList();

  @override
  Future<List<ArticleModel>> getArticlesByCategory(String category, {int limit = 100}) async =>
      _store.values.toList();

  @override
  Future<List<ArticleModel>> getArticles({String? category, String? sourceId, int limit = 100, int offset = 0}) async =>
      _store.values.toList();

  @override
  Future<ArticleModel?> getArticleById(String id) async => _store[id];

  @override
  Future<List<ArticleModel>> getFavorites() async => const [];

  @override
  Future<void> markAsRead(String id) async {}

  @override
  Future<void> toggleFavorite(String id) async {}

  @override
  Future<List<ArticleModel>> searchArticles(String query, {int limit = 100}) async => const [];

  @override
  Future<int> pruneOldArticles({Duration retentionPeriod = const Duration(days: 30), DateTime? referenceTimeUtc}) async => 0;

  @override
  Future<int> clearArticles({bool keepFavorites = false}) async => 0;
}

class _FakeTestNewsRepository implements NewsRepository {
  _FakeTestNewsRepository({
    required this.localDataSource,
    required this.registry,
  });

  final NewsLocalDataSource localDataSource;
  final NewsSourceRegistry registry;

  @override
  Future<List<Article>> getArticlesForReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<String> sourceIds,
  }) async {
    final models = await localDataSource.getArticlesForReport(
      startUtc: startUtc,
      endUtc: endUtc,
      sourceIds: sourceIds,
    );
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<SyncResult> syncSelectedSources([List<NewsSource>? sources]) async {
    final targetSources = sources ?? registry.getEnabledSources();
    final allArticles = <ArticleModel>[];
    String? warning;

    for (final s in targetSources) {
      try {
        final batch = await s.fetchLatestArticles();
        allArticles.addAll(batch);
      } catch (e) {
        warning = 'No fue posible sincronizar con ${s.name}.';
      }
    }

    if (allArticles.isNotEmpty) {
      await localDataSource.upsertArticles(allArticles);
    }

    return SyncResult(
      fetched: allArticles.length,
      inserted: allArticles.length,
      syncedAt: DateTime.now().toUtc(),
      warning: warning,
    );
  }

  @override
  Future<SyncResult> syncLatestArticles() async => syncSelectedSources();

  @override
  Future<List<Article>> getLatestArticles({int limit = 100}) async => const [];

  @override
  Future<List<Article>> getArticlesByCategory(String category, {int limit = 100}) async => const [];

  @override
  Future<List<Article>> getArticles({String? category, String? sourceId, int limit = 100, int offset = 0}) async => const [];

  @override
  Future<Article?> getArticleById(String id) async => null;

  @override
  Future<List<Article>> getFavorites() async => const [];

  @override
  Future<void> markAsRead(String id) async {}

  @override
  Future<void> toggleFavorite(String id) async {}

  @override
  Future<List<Article>> searchArticles(String query, {int limit = 100}) async => const [];

  @override
  Future<int> pruneOldArticles({Duration retentionPeriod = const Duration(days: 30), DateTime? referenceTimeUtc}) async => 0;

  @override
  Future<int> clearCache({bool keepFavorites = false}) async => 0;
}

class _MockNewsSource implements NewsSource {
  _MockNewsSource(this.id, this.name, this.articles);

  @override
  final String id;
  @override
  final String name;
  @override
  int get sortOrder => 1;
  final List<ArticleModel> articles;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async => articles;
}

class _MockFailingNewsSource implements NewsSource {
  _MockFailingNewsSource(this.id, this.name);

  @override
  final String id;
  @override
  final String name;
  @override
  int get sortOrder => 1;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    throw Exception('Simulated network failure on $name');
  }
}

class _InMemoryTestPreferences implements AppPreferencesDataSource {
  bool hourlyEnabled = true;
  String? lastWindow;
  bool modeAll = true;
  List<String> selectedSources = const [];

  @override
  Future<bool> getHourlyReportsEnabled({bool reload = false}) async => hourlyEnabled;

  @override
  Future<void> setHourlyReportsEnabled(bool enabled) async {
    hourlyEnabled = enabled;
  }

  @override
  Future<String?> getLastHourlyReportWindowNotified({bool reload = false}) async => lastWindow;

  @override
  Future<void> setLastHourlyReportWindowNotified(String windowId) async {
    lastWindow = windowId;
  }

  @override
  Future<bool> getReportSourcesModeAll({bool reload = false}) async => modeAll;

  @override
  Future<void> setReportSourcesModeAll(bool isAll) async {
    modeAll = isAll;
  }

  @override
  Future<List<String>> getReportSelectedSourceIds({bool reload = false}) async => selectedSources;

  @override
  Future<void> setReportSelectedSourceIds(List<String> sourceIds) async {
    selectedSources = sourceIds;
  }

  @override
  Future<bool> getNotificationsEnabled({bool reload = false}) async => true;
  @override
  Future<void> setNotificationsEnabled(bool enabled) async {}
  @override
  Future<bool> getBackgroundSyncEnabled({bool reload = false}) async => true;
  @override
  Future<void> setBackgroundSyncEnabled(bool enabled) async {}
  @override
  Future<Set<String>> getSeededSourceIds({bool reload = false}) async => const <String>{};
  @override
  Future<void> setSourceSeeded(String sourceId) async {}
  @override
  Future<void> clearSeededSources() async {}
  @override
  Future<bool> getAutoRefreshOnOpen({bool reload = false}) async => true;
  @override
  Future<void> setAutoRefreshOnOpen(bool enabled) async {}
  @override
  Future<bool> isCacheClearedPendingBaseline({bool reload = false}) async => false;
  @override
  Future<void> setCacheClearedPendingBaseline(bool value) async {}
  @override
  Future<bool> getEasterEggUnlocked({bool reload = false}) async => false;
  @override
  Future<void> setEasterEggUnlocked(bool unlocked) async {}
}

class _RecordingTestNotificationGateway implements NotificationGateway {
  final List<({String windowLabel, int articleCount, DateTime startUtc, DateTime endUtc})>
      dispatchedHourlyReports = [];

  @override
  Future<void> showHourlyReportNotification({
    required String windowLabel,
    required int articleCount,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    dispatchedHourlyReports.add((
      windowLabel: windowLabel,
      articleCount: articleCount,
      startUtc: startUtc,
      endUtc: endUtc,
    ));
  }

  @override
  Future<void> initialize({bool isBackgroundIsolate = false}) async {}
  @override
  Future<void> notifyNewArticles(List<Article> newArticles) async {}
  @override
  Future<void> showDebugTestNotification() async {}
}
