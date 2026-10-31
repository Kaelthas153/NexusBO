import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/reports/domain/models/monitoring_report.dart';

/// Servicio de lógica pura para construcción, cálculo de ventanas y agrupación
/// de reportes de monitoreo por rango horario.
abstract final class MonitoringReportService {
  /// Determina si un rango horario solicitado es "reciente" (hoy o dentro de las últimas 24 horas),
  /// lo que justifica un intento previo de sincronización con las fuentes antes de consultar SQLite.
  static bool isRecentRange(
    DateTime startUtc,
    DateTime endUtc, {
    DateTime? nowUtc,
  }) {
    final now = nowUtc?.toUtc() ?? DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(hours: 24));
    // Es reciente si el final o el inicio se solapan con las últimas 24 horas o el futuro
    return endUtc.isAfter(cutoff);
  }

  /// Calcula la última hora COMPLETA en hora oficial de Bolivia (UTC-4)
  /// devolviendo los límites en UTC y en hora local.
  ///
  /// Ejemplo:
  /// Si en Bolivia son las 10:53 -> devuelve 09:00 a 10:00.
  /// Si son las 09:03 -> devuelve 08:00 a 09:00.
  /// Si son las 00:15 del 31/10 -> devuelve 23:00 del 30/10 a 00:00 del 31/10.
  static ({
    DateTime startUtc,
    DateTime endUtc,
    DateTime startBolivia,
    DateTime endBolivia,
    String windowId,
  }) calculateLastCompleteHourWindow({DateTime? referenceUtc}) {
    final nowUtc = referenceUtc?.toUtc() ?? DateTime.now().toUtc();
    final nowBolivia = BoliviaDateFormatter.toBoliviaTime(nowUtc);

    final endBolivia = DateTime(
      nowBolivia.year,
      nowBolivia.month,
      nowBolivia.day,
      nowBolivia.hour,
      0,
      0,
    );

    final startBolivia = endBolivia.subtract(const Duration(hours: 1));

    final startUtc = BoliviaDateFormatter.boliviaTimeToUtc(startBolivia);
    final endUtc = BoliviaDateFormatter.boliviaTimeToUtc(endBolivia);

    // Identificador único y determinista para persistencia y prevención de duplicados
    final windowId = '${startUtc.millisecondsSinceEpoch}_${endUtc.millisecondsSinceEpoch}';

    return (
      startUtc: startUtc,
      endUtc: endUtc,
      startBolivia: startBolivia,
      endBolivia: endBolivia,
      windowId: windowId,
    );
  }

  /// Construye un [MonitoringReport] a partir de una colección de artículos obtenidos de SQLite,
  /// agrupándolos por medio según el orden de [orderedSources] y ordenándolos cronológicamente
  /// en forma ascendente (`publishedAt ASC`) dentro de cada sección.
  static MonitoringReport buildReport({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<ArticleModel> articles,
    required List<NewsSource> orderedSources,
    String? syncWarning,
  }) {
    final sections = <ReportSection>[];

    // Agrupar respetando el orden del registro de fuentes
    for (final source in orderedSources) {
      final sourceArticles = articles
          .where((a) => a.sourceId.toLowerCase() == source.id.toLowerCase())
          .toList()
        ..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));

      if (sourceArticles.isNotEmpty) {
        sections.add(
          ReportSection(
            sourceId: source.id,
            sourceName: source.name,
            articles: List<ArticleModel>.unmodifiable(sourceArticles),
          ),
        );
      }
    }

    // Si existen artículos con fuentes que no estén en orderedSources, agruparlos al final
    final knownSourceIds = orderedSources.map((s) => s.id.toLowerCase()).toSet();
    final remainingArticles = articles
        .where((a) => !knownSourceIds.contains(a.sourceId.toLowerCase()))
        .toList();

    if (remainingArticles.isNotEmpty) {
      final groupedByName = <String, List<ArticleModel>>{};
      for (final a in remainingArticles) {
        groupedByName.putIfAbsent(a.sourceName, () => <ArticleModel>[]).add(a);
      }
      for (final entry in groupedByName.entries) {
        entry.value.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
        sections.add(
          ReportSection(
            sourceId: entry.value.first.sourceId,
            sourceName: entry.key,
            articles: List<ArticleModel>.unmodifiable(entry.value),
          ),
        );
      }
    }

    return MonitoringReport(
      startUtc: startUtc,
      endUtc: endUtc,
      sections: List<ReportSection>.unmodifiable(sections),
      totalArticles: articles.length,
      generatedAtUtc: DateTime.now().toUtc(),
      syncWarning: syncWarning,
    );
  }
}

