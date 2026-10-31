import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/reports/domain/models/monitoring_report.dart';

/// Formateador editorial para reportes de monitoreo optimizados para portapapeles y WhatsApp.
abstract final class MonitoringReportFormatter {
  /// Genera la cabecera del reporte según las especificaciones de formato:
  /// - Mismo día: `*MONITOREO DD/MM/YYYY hh:mm am - hh:mm am*`
  /// - Cruce de medianoche: `*MONITOREO DD/MM/YYYY hh:mm am - DD/MM/YYYY hh:mm am*`
  static String buildHeader(DateTime startUtc, DateTime endUtc) {
    final startBolivia = BoliviaDateFormatter.toBoliviaTime(startUtc);
    final endBolivia = BoliviaDateFormatter.toBoliviaTime(endUtc);

    final startDateStr = BoliviaDateFormatter.formatDayMonthYear(startBolivia);
    final startTimeStr = BoliviaDateFormatter.format12Hour(startBolivia);
    final endTimeStr = BoliviaDateFormatter.format12Hour(endBolivia);

    final isSameDay = startBolivia.year == endBolivia.year &&
        startBolivia.month == endBolivia.month &&
        startBolivia.day == endBolivia.day;

    if (isSameDay) {
      return '*MONITOREO $startDateStr $startTimeStr - $endTimeStr*';
    } else {
      final endDateStr = BoliviaDateFormatter.formatDayMonthYear(endBolivia);
      return '*MONITOREO $startDateStr $startTimeStr - $endDateStr $endTimeStr*';
    }
  }

  /// Selecciona y limpia el resumen ideal para el reporte de WhatsApp (~200 a 350 caracteres,
  /// cortando en límite de oración sin truncar palabras arbitrariamente ni repetir el título).
  static String extractCleanSummary(ArticleModel article) {
    final titleClean = article.title.trim().toLowerCase();

    // 1. Probar con article.summary si es válido y no repite el título
    String candidate = article.summary.trim();
    if (candidate.isEmpty || candidate.toLowerCase() == titleClean) {
      // 2. Si no, extraer el primer párrafo útil de contentPlain
      final paragraphs = article.contentPlain
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty && p.toLowerCase() != titleClean);
      candidate = paragraphs.firstOrNull ?? '';
    }

    if (candidate.isEmpty) {
      candidate = article.contentPlain.trim();
    }

    if (candidate.isEmpty || candidate.toLowerCase() == titleClean) {
      return '';
    }

    // Normalizar espacios internos
    candidate = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Si ya tiene una longitud adecuada (<= 350 chars), conservarlo íntegro
    if (candidate.length <= 350) {
      return candidate;
    }

    // Buscar el final de oración más natural entre 180 y 350 caracteres
    final searchZone = candidate.substring(0, 350);
    final lastSentenceEnd = searchZone.lastIndexOf(RegExp(r'[.!?](?:\s|$)'));

    if (lastSentenceEnd >= 180) {
      return candidate.substring(0, lastSentenceEnd + 1).trim();
    }

    // Si no hay punto oracional claro en esa zona, cortar por la última palabra completa
    final lastSpace = searchZone.lastIndexOf(' ');
    if (lastSpace >= 180) {
      return '${candidate.substring(0, lastSpace).trim()}...';
    }

    return '${searchZone.trim()}...';
  }

  /// Construye el texto plano íntegro del reporte, listo para WhatsApp sin escapar asteriscos ni links.
  static String formatWhatsApp(MonitoringReport report) {
    if (report.isEmpty) {
      return 'No se encontraron noticias publicadas en este rango.';
    }

    final buffer = StringBuffer();
    buffer.writeln(buildHeader(report.startUtc, report.endUtc));

    for (final section in report.sections) {
      if (section.articles.isEmpty) continue;

      buffer.writeln();
      buffer.writeln('*${section.sourceName}*');

      for (final article in section.articles) {
        buffer.writeln();
        buffer.writeln('- ${article.title.trim()}');

        final summary = extractCleanSummary(article);
        if (summary.isNotEmpty) {
          buffer.writeln(summary);
        }

        buffer.writeln(article.url.trim());
      }
    }

    return buffer.toString().trim();
  }
}

