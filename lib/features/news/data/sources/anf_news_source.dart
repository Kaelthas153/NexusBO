import 'package:html/parser.dart' as html_parser;
import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Implementación de [NewsSource] para la Agencia de Noticias Fides (ANF).
///
/// Descubre despachos informativos desde la portada (`https://www.noticiasfides.com/`),
/// extrayendo categorías directamente de la estructura canónica `/nacional/categoria/slug`
/// y enriqueciendo el cuerpo completo y metadatos OpenGraph de forma selectiva para
/// artículos nuevos no registrados en SQLite.
class AnfNewsSource implements NewsSource {
  AnfNewsSource({
    required DioClient dioClient,
    NewsLocalDataSource? localDataSource,
    String homeUrl = ApiConstants.anfHomeUrl,
    bool enrichNewArticles = true,
    int maxEnrichmentCount = 5,
  }) : _dioClient = dioClient,
       _localDataSource = localDataSource,
       _homeUrl = homeUrl,
       _enrichNewArticles = enrichNewArticles,
       _maxEnrichmentCount = maxEnrichmentCount;

  final DioClient _dioClient;
  final NewsLocalDataSource? _localDataSource;
  final String _homeUrl;
  final bool _enrichNewArticles;
  final int _maxEnrichmentCount;

  @override
  String get id => ApiConstants.anfSourceId; // 'anf'

  @override
  String get name => ApiConstants.anfSourceName; // 'ANF'

  @override
  int get sortOrder => 9;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawHtml = await _dioClient.getRawString(
      _homeUrl,
      headers: const <String, Object>{
        'User-Agent': ApiConstants.browserUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );

    final preliminary = parseArticleLinks(rawHtml);
    if (preliminary.isEmpty) {
      return preliminary;
    }

    final enriched = <ArticleModel>[];
    var enrichmentAttempts = 0;

    for (final article in preliminary) {
      // 1. Si ya existe en SQLite con contenido completo, conservar versión local
      if (_localDataSource != null) {
        try {
          final cached = await _localDataSource.getArticleById(article.id);
          if (cached != null && cached.contentPlain.length > 80) {
            enriched.add(
              article.copyWith(
                title: cached.title.isNotEmpty ? cached.title : article.title,
                summary: cached.summary.isNotEmpty ? cached.summary : article.summary,
                contentPlain: cached.contentPlain,
                author: cached.author,
                imageUrl: cached.imageUrl ?? article.imageUrl,
                imageUrls: cached.imageUrls.isNotEmpty ? cached.imageUrls : article.imageUrls,
                publishedAt: cached.publishedAt,
              ),
            );
            continue;
          }
        } catch (_) {
          // Continuar normalmente ante excepciones de lectura local
        }
      }

      // 2. Enriquecer con OpenGraph y párrafos de la nota para artículos nuevos
      if (_enrichNewArticles && enrichmentAttempts < _maxEnrichmentCount) {
        enrichmentAttempts++;
        try {
          final enrichedArticle = await _enrichArticleDetail(article);
          enriched.add(enrichedArticle);
          continue;
        } catch (_) {
          // Fallback seguro a la versión preliminar si falla la página de detalle
        }
      }

      enriched.add(article);
    }

    return enriched;
  }

  /// Descubre enlaces a artículos en el HTML de portada de ANF.
  static List<ArticleModel> parseArticleLinks(String html) {
    if (html.trim().isEmpty) return const <ArticleModel>[];

    final doc = html_parser.parse(html);
    final links = doc.querySelectorAll('a[href]');
    final articles = <ArticleModel>[];
    final seenIds = <String>{};
    final nowUtc = DateTime.now().toUtc();

    for (final a in links) {
      final href = a.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href.startsWith('#') || href.contains('redirectad') || href.contains('facebook.com')) {
        continue;
      }

      // Enlaces canónicos: /nacional/categoria/slug o /categoria/slug
      final uri = Uri.tryParse(href);
      final segments = (uri?.pathSegments ?? href.split('/'))
          .where((s) => s.isNotEmpty)
          .toList();

      if (segments.length < 2) continue;

      // Descartar si el último segmento no tiene guiones (páginas de sección como /nacional/politica)
      final slug = segments.last;
      if (!slug.contains('-') || slug.length < 10) continue;

      final id = 'anf_$slug';
      if (seenIds.contains(id)) continue;
      seenIds.add(id);

      final fullUrl = href.startsWith('http')
          ? href
          : 'https://www.noticiasfides.com${href.startsWith('/') ? '' : '/'}$href';

      // Extraer categoría del penúltimo segmento o anterior
      final categorySegment = segments.length >= 3 ? segments[segments.length - 2] : segments.first;
      final category = CategoryMapper.toCanonical(categorySegment);

      var titleText = a.text.trim();
      if (titleText.length < 15) {
        final parent = a.parent;
        final candidate = parent?.querySelector('h2, h3, h4, .title')?.text.trim();
        if (candidate != null && candidate.length > 15) {
          titleText = candidate;
        } else {
          titleText = slug.replaceAll('-', ' ');
          if (titleText.isNotEmpty) {
            titleText = titleText[0].toUpperCase() + titleText.substring(1);
          }
        }
      }

      articles.add(
        ArticleModel(
          id: id,
          title: HtmlSanitizer.decodeHtmlEntities(titleText),
          summary: HtmlSanitizer.decodeHtmlEntities(titleText),
          contentPlain: HtmlSanitizer.decodeHtmlEntities(titleText),
          url: fullUrl,
          author: ApiConstants.anfSourceName,
          sourceId: ApiConstants.anfSourceId,
          sourceName: ApiConstants.anfSourceName,
          category: category,
          tags: <String>['ANF', CategoryMapper.toDisplay(category)],
          publishedAt: nowUtc,
          fetchedAt: nowUtc,
        ),
      );
    }

    return articles;
  }

  Future<ArticleModel> _enrichArticleDetail(ArticleModel article) async {
    final rawHtml = await _dioClient.getRawString(
      article.url,
      headers: const <String, Object>{
        'User-Agent': ApiConstants.browserUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );

    final doc = html_parser.parse(rawHtml);

    final ogTitle = doc.querySelector('meta[property="og:title"]')?.attributes['content'];
    final ogDesc = doc.querySelector('meta[property="og:description"]')?.attributes['content'];
    final ogImage = doc.querySelector('meta[property="og:image"]')?.attributes['content'];

    final pElements = doc.querySelectorAll('article p, .cuerpo p, .nota-cuerpo p, .content p, p');

    final paragraphs = pElements
        .map((p) => HtmlSanitizer.decodeHtmlEntities(p.text))
        .where((t) =>
            t.length > 25 &&
            !t.toLowerCase().contains('todos los derechos reservados') &&
            !t.toLowerCase().contains('agencia de noticias fides') &&
            !t.startsWith('/cdn-cgi/'))
        .toList(growable: false);

    final cleanTitle = (ogTitle != null && ogTitle.trim().isNotEmpty)
        ? _sanitizeAnfTitle(ogTitle)
        : article.title;

    final cleanSummary = (ogDesc != null && ogDesc.trim().isNotEmpty)
        ? HtmlSanitizer.decodeHtmlEntities(ogDesc)
        : (paragraphs.isNotEmpty ? paragraphs.first : article.summary);

    final cleanImage = (ogImage != null && ogImage.trim().isNotEmpty)
        ? (ogImage.startsWith('http') ? ogImage.trim() : 'https://www.noticiasfides.com${ogImage.trim()}')
        : article.imageUrl;

    final fullContent = paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : cleanSummary;

    // Intentar deducir la fecha desde el dateline boliviano en el primer párrafo (ej. "La Paz, 1 de septiembre de 2026 (ANF).-")
    DateTime publishedAt = article.publishedAt;
    if (paragraphs.isNotEmpty) {
      final parsedDate = _extractDateFromDateline(paragraphs.first);
      if (parsedDate != null) {
        publishedAt = parsedDate;
      }
    }

    return article.copyWith(
      title: cleanTitle,
      summary: cleanSummary,
      contentPlain: fullContent,
      imageUrl: cleanImage,
      imageUrls: cleanImage != null ? <String>[cleanImage] : article.imageUrls,
      publishedAt: publishedAt,
    );
  }

  static String _sanitizeAnfTitle(String rawTitle) {
    var title = rawTitle.replaceAll(RegExp(r'\s*-\s*Agencias? de Noticias Fides.*$', caseSensitive: false), '');
    return HtmlSanitizer.decodeHtmlEntities(title);
  }

  static DateTime? _extractDateFromDateline(String firstParagraph) {
    final match = RegExp(
      r'(\d{1,2})\s+de\s+([a-zA-ZáéíóúÁÉÍÓÚ]+)\s+de\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(firstParagraph);

    if (match != null) {
      try {
        final day = int.parse(match.group(1)!);
        final monthName = match.group(2)!.toLowerCase();
        final year = int.parse(match.group(3)!);
        final month = _monthNumberFromName(monthName);
        if (month != null) {
          // Considerar mediodía en hora boliviana (12:00 BOT = 16:00 UTC)
          final boliviaTime = DateTime(year, month, day, 12, 0);
          return BoliviaDateFormatter.boliviaTimeToUtc(boliviaTime);
        }
      } catch (_) {}
    }
    return null;
  }

  static int? _monthNumberFromName(String month) {
    switch (month) {
      case 'enero':
        return 1;
      case 'febrero':
        return 2;
      case 'marzo':
        return 3;
      case 'abril':
        return 4;
      case 'mayo':
        return 5;
      case 'junio':
        return 6;
      case 'julio':
        return 7;
      case 'agosto':
        return 8;
      case 'septiembre':
      case 'setiembre':
        return 9;
      case 'octubre':
        return 10;
      case 'noviembre':
        return 11;
      case 'diciembre':
        return 12;
      default:
        return null;
    }
  }
}
