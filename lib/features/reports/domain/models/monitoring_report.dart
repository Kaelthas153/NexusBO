import 'package:flutter/foundation.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';

/// Sección de un reporte de monitoreo agrupada por medio de comunicación.
@immutable
class ReportSection {
  const ReportSection({
    required this.sourceId,
    required this.sourceName,
    required this.articles,
  });

  final String sourceId;
  final String sourceName;
  final List<ArticleModel> articles;

  int get count => articles.length;

  @override
  String toString() => 'ReportSection(source: $sourceName, articles: ${articles.length})';
}

/// Modelo de dominio inmutable que representa un reporte de monitoreo por rango horario.
///
/// Los reportes se construyen dinámicamente desde SQLite y nunca se almacenan como copias redundantes.
@immutable
class MonitoringReport {
  const MonitoringReport({
    required this.startUtc,
    required this.endUtc,
    required this.sections,
    required this.totalArticles,
    required this.generatedAtUtc,
    this.syncWarning,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final List<ReportSection> sections;
  final int totalArticles;
  final DateTime generatedAtUtc;
  final String? syncWarning;

  bool get isEmpty => totalArticles == 0;
  bool get isNotEmpty => totalArticles > 0;
  int get activeSourcesCount => sections.where((s) => s.articles.isNotEmpty).length;

  @override
  String toString() =>
      'MonitoringReport($startUtc - $endUtc, articles: $totalArticles, sections: ${sections.length})';
}

