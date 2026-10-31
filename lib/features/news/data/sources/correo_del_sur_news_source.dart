import 'package:html/parser.dart' as html_parser;
import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Implementación de [NewsSource] para Correo del Sur (Sucre / Chuquisaca).
///
/// Parsea el HTML Server-Side Rendered (Astro) de la portada (`https://correodelsur.com/`).
/// Extrae noticias desde los elementos `<ku-card>`, generando IDs deterministas
/// bajo el formato `correodelsur_YYYYMMDD_slug` y realizando enriquecimiento
/// de cuerpo completo controlado únicamente para artículos nuevos.
class CorreoDelSurNewsSource implements NewsSource {
  CorreoDelSurNewsSource({
    required DioClient dioClient,
    NewsLocalDataSource? localDataSource,
    String homeUrl = ApiConstants.correoDelSurHomeUrl,
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
  String get id => ApiConstants.correoDelSurSourceId; // 'correodelsur'

  @override
  String get name => ApiConstants.correoDelSurSourceName; // 'Correo del Sur'

  @override
  int get sortOrder => 7;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawHtml = await _dioClient.getRawString(
      _homeUrl,
      headers: const <String, Object>{
        'User-Agent': ApiConstants.browserUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );

    final preliminary = parseCards(rawHtml);
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
                summary: cached.summary.isNotEmpty ? cached.summary : article.summary,
                contentPlain: cached.contentPlain,
                author: cached.author,
                imageUrl: cached.imageUrl ?? article.imageUrl,
                imageUrls: cached.imageUrls.isNotEmpty ? cached.imageUrls : article.imageUrls,
              ),
            );
            continue;
          }
        } catch (_) {
          // Continuar normalmente si falla la lectura local
        }
      }

      // 2. Enriquecer con cuerpo completo si no está en SQLite (hasta el límite de concurrencia)
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

  /// Parsea elementos `<ku-card>` o enlaces editoriales de la portada de Correo del Sur.
  static List<ArticleModel> parseCards(String html) {
    if (html.trim().isEmpty) return const <ArticleModel>[];

    final doc = html_parser.parse(html);
    final kuCards = doc.querySelectorAll('ku-card');
    final articles = <ArticleModel>[];
    final seenIds = <String>{};

    final nowUtc = DateTime.now().toUtc();

    for (final card in kuCards) {
      final titleAttr = card.attributes['title']?.trim();
      final urlAttr = card.attributes['url']?.trim();

      if (titleAttr == null || titleAttr.isEmpty || urlAttr == null || urlAttr.isEmpty) {
        continue;
      }

      final normalizedUrl = urlAttr.startsWith('http')
          ? urlAttr
          : 'https://correodelsur.com${urlAttr.startsWith('/') ? '' : '/'}$urlAttr';

      final id = _generateIdFromUrl(normalizedUrl, titleAttr);
      if (seenIds.contains(id)) continue;
      seenIds.add(id);

      final authorAttr = card.attributes['author']?.trim();
      final introAttr = card.attributes['introduction']?.trim();
      final sectionAttr = card.attributes['section-title']?.trim();
      final imageAttr = card.attributes['image-url']?.trim();
      final createdAtAttr = card.attributes['created-at']?.trim();

      final publishedAt = _parseCreatedAt(createdAtAttr, normalizedUrl, nowUtc);
      final category = _resolveCategory(sectionAttr, normalizedUrl);

      final summary = (introAttr != null && introAttr.isNotEmpty)
          ? HtmlSanitizer.decodeHtmlEntities(introAttr)
          : titleAttr;

      final validImage = (imageAttr != null && imageAttr.isNotEmpty)
          ? (imageAttr.startsWith('http') ? imageAttr : 'https://cdn.correodelsur.com$imageAttr')
          : null;

      final imageUrls = validImage != null ? <String>[validImage] : const <String>[];

      articles.add(
        ArticleModel(
          id: id,
          title: HtmlSanitizer.decodeHtmlEntities(titleAttr),
          summary: summary,
          contentPlain: summary,
          url: normalizedUrl,
          imageUrl: validImage,
          imageUrls: imageUrls,
          author: (authorAttr != null && authorAttr.isNotEmpty)
              ? HtmlSanitizer.decodeHtmlEntities(authorAttr)
              : ApiConstants.correoDelSurSourceName,
          sourceId: ApiConstants.correoDelSurSourceId,
          sourceName: ApiConstants.correoDelSurSourceName,
          category: category,
          tags: <String>['Correo del Sur', CategoryMapper.toDisplay(category)],
          publishedAt: publishedAt,
          fetchedAt: nowUtc,
        ),
      );
    }

    return articles;
  }

  Future<ArticleModel> _enrichArticleDetail(ArticleModel article) async {
    final rawDetailHtml = await _dioClient.getRawString(
      article.url,
      headers: const <String, Object>{
        'User-Agent': ApiConstants.browserUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );

    final doc = html_parser.parse(rawDetailHtml);
    final paragraphs = doc.querySelectorAll(
      'article p, .cuerpo p, .nota-cuerpo p, .content p, .article-content p, main p',
    );

    final cleanedParas = paragraphs
        .map((p) => HtmlSanitizer.decodeHtmlEntities(p.text))
        .where((text) =>
            text.length > 20 &&
            !text.toLowerCase().contains('correo del sur todos los derechos') &&
            !text.toLowerCase().contains('espacio publicitario'))
        .toList(growable: false);

    if (cleanedParas.isEmpty) {
      return article;
    }

    final fullContent = cleanedParas.join('\n\n');
    final cleanSummary = cleanedParas.first.length > 300
        ? '${cleanedParas.first.substring(0, 297)}...'
        : cleanedParas.first;

    // Buscar imágenes adicionales en el cuerpo del artículo
    final detailImages = <String>[];
    if (article.imageUrl != null) {
      detailImages.add(article.imageUrl!);
    }
    for (final img in doc.querySelectorAll('article img, .cuerpo img, main img')) {
      final src = img.attributes['src']?.trim() ?? img.attributes['data-src']?.trim();
      if (src != null && src.isNotEmpty && !src.contains('publicidad') && !src.contains('logo')) {
        final fullSrc = src.startsWith('http') ? src : 'https://correodelsur.com$src';
        if (!detailImages.contains(fullSrc)) {
          detailImages.add(fullSrc);
        }
      }
    }

    return article.copyWith(
      summary: article.summary.isNotEmpty ? article.summary : cleanSummary,
      contentPlain: fullContent,
      imageUrls: detailImages.isNotEmpty ? detailImages : article.imageUrls,
    );
  }

  static String _generateIdFromUrl(String url, String fallbackTitle) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2) {
        // e.g. ["seguridad", "20261031", "estamos-en-momentos-dificiles....html"]
        var datePart = '';
        var slugPart = '';
        for (final s in segments) {
          if (RegExp(r'^\d{8}$').hasMatch(s)) {
            datePart = s;
          } else if (s.endsWith('.html') || s.contains('-')) {
            slugPart = s.replaceAll('.html', '');
          }
        }
        if (datePart.isNotEmpty && slugPart.isNotEmpty) {
          return 'correodelsur_${datePart}_$slugPart';
        }
        if (slugPart.isNotEmpty) {
          return 'correodelsur_$slugPart';
        }
      }
    } catch (_) {}

    final slug = fallbackTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'correodelsur_$slug';
  }

  static DateTime _parseCreatedAt(String? createdAtAttr, String url, DateTime nowUtc) {
    // 1. Extraer fecha base desde la URL (YYYYMMDD) si existe
    DateTime? urlDate;
    final match = RegExp(r'/(\d{4})(\d{2})(\d{2})/').firstMatch(url);
    if (match != null) {
      try {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        urlDate = DateTime.utc(year, month, day, 12, 0);
      } catch (_) {}
    }

    if (createdAtAttr == null || createdAtAttr.trim().isEmpty) {
      return urlDate ?? nowUtc;
    }

    final lower = createdAtAttr.toLowerCase().trim();
    if (lower.contains('instantes') || lower.contains('minuto')) {
      return nowUtc;
    }
    final hoursMatch = RegExp(r'hace\s+(\d+)\s+hora').firstMatch(lower);
    if (hoursMatch != null) {
      final hours = int.tryParse(hoursMatch.group(1)!) ?? 1;
      return nowUtc.subtract(Duration(hours: hours));
    }
    if (lower.contains('hace una hora')) {
      return nowUtc.subtract(const Duration(hours: 1));
    }

    return urlDate ?? nowUtc;
  }

  static String _resolveCategory(String? sectionTitle, String url) {
    if (sectionTitle != null && sectionTitle.trim().isNotEmpty) {
      return CategoryMapper.toCanonical(sectionTitle.trim());
    }
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return CategoryMapper.toCanonical(segments.first);
      }
    } catch (_) {}
    return CategoryMapper.canonicalGeneral;
  }
}
