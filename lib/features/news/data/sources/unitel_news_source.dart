import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Implementación de [NewsSource] para Unitel (Red televisiva y digital nacional).
///
/// Descubre artículos desde el portal de noticias (`https://unitel.bo/noticias`),
/// extrayendo identificadores únicos de artículo (`unitel_ID`), y enriquece los
/// detalles utilizando los datos estructurados JSON-LD (`NewsArticle`) oficiales
/// presentes en cada nota, optimizando peticiones concurrentes y cacheando resultados.
class UnitelNewsSource implements NewsSource {
  UnitelNewsSource({
    required DioClient dioClient,
    NewsLocalDataSource? localDataSource,
    String newsUrl = ApiConstants.unitelNewsUrl,
    bool enrichNewArticles = true,
    int maxEnrichmentCount = 5,
  }) : _dioClient = dioClient,
       _localDataSource = localDataSource,
       _newsUrl = newsUrl,
       _enrichNewArticles = enrichNewArticles,
       _maxEnrichmentCount = maxEnrichmentCount;

  final DioClient _dioClient;
  final NewsLocalDataSource? _localDataSource;
  final String _newsUrl;
  final bool _enrichNewArticles;
  final int _maxEnrichmentCount;

  @override
  String get id => ApiConstants.unitelSourceId; // 'unitel'

  @override
  String get name => ApiConstants.unitelSourceName; // 'Unitel'

  @override
  int get sortOrder => 8;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawHtml = await _dioClient.getRawString(
      _newsUrl,
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

      // 2. Enriquecer con JSON-LD únicamente para artículos nuevos (respetando límite de concurrencia)
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

  /// Descubre enlaces de artículos en el listado HTML de Unitel.
  static List<ArticleModel> parseArticleLinks(String html) {
    if (html.trim().isEmpty) return const <ArticleModel>[];

    final doc = html_parser.parse(html);
    final links = doc.querySelectorAll('a[href]');
    final articles = <ArticleModel>[];
    final seenIds = <String>{};
    final nowUtc = DateTime.now().toUtc();

    for (final a in links) {
      final href = a.attributes['href']?.trim() ?? '';
      if (!href.contains('/noticias/')) continue;

      // Descartar enlaces de sección pura como /noticias/santa-cruz o /noticias/la-paz
      final uri = Uri.tryParse(href);
      final segments = (uri?.pathSegments ?? href.split('/'))
          .where((s) => s.isNotEmpty && s != 'noticias')
          .toList();

      if (segments.length < 2) continue;

      // El último segmento suele tener la forma 'slug-articuloid' (e.g. '...-ND24502168')
      final lastSegment = segments.last;
      final articleIdMatch = RegExp(r'-([A-Z0-9]{8,12})$').firstMatch(lastSegment);
      final uniqueRawId = articleIdMatch != null ? articleIdMatch.group(1)! : lastSegment;

      final id = 'unitel_$uniqueRawId';
      if (seenIds.contains(id)) continue;
      seenIds.add(id);

      final fullUrl = href.startsWith('http') ? href : 'https://unitel.bo$href';
      final preliminaryCategory = CategoryMapper.toCanonical(segments.first);

      var titleText = a.text.trim();
      if (titleText.length < 15) {
        // Si el enlace era solo una imagen, buscar elemento hermano o titular cercano
        final parent = a.parent;
        final candidateTitle = parent?.querySelector('h2, h3, .title, .headline')?.text.trim();
        if (candidateTitle != null && candidateTitle.length > 15) {
          titleText = candidateTitle;
        } else {
          // Reconstruir título preliminar legible desde el slug
          final slugClean = lastSegment.replaceAll(RegExp(r'-[A-Z0-9]{8,12}$'), '');
          titleText = slugClean.replaceAll('-', ' ').trim();
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
          author: ApiConstants.unitelSourceName,
          sourceId: ApiConstants.unitelSourceId,
          sourceName: ApiConstants.unitelSourceName,
          category: preliminaryCategory,
          tags: <String>['Unitel', CategoryMapper.toDisplay(preliminaryCategory)],
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

    // 1. Intentar extracción desde JSON-LD oficial
    for (final script in doc.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(script.text);
        final articleJson = _extractNewsArticleJson(decoded);
        if (articleJson != null) {
          return _buildFromNewsArticleJson(article, articleJson);
        }
      } catch (_) {
        // Ignorar scripts JSON-LD secundarios o malformados
      }
    }

    // 2. Fallback a OpenGraph y etiquetas semánticas HTML
    final ogTitle = doc.querySelector('meta[property="og:title"]')?.attributes['content'];
    final ogDesc = doc.querySelector('meta[property="og:description"]')?.attributes['content'];
    final ogImage = doc.querySelector('meta[property="og:image"]')?.attributes['content'];
    final pElements = doc.querySelectorAll('article p, .story-body p, .article-body p');

    final paragraphs = pElements
        .map((p) => HtmlSanitizer.decodeHtmlEntities(p.text))
        .where((t) => t.length > 20)
        .toList(growable: false);

    final cleanTitle = (ogTitle != null && ogTitle.trim().isNotEmpty)
        ? HtmlSanitizer.decodeHtmlEntities(ogTitle)
        : article.title;

    final cleanSummary = (ogDesc != null && ogDesc.trim().isNotEmpty)
        ? HtmlSanitizer.decodeHtmlEntities(ogDesc)
        : (paragraphs.isNotEmpty ? paragraphs.first : article.summary);

    final cleanImage = (ogImage != null && ogImage.trim().isNotEmpty)
        ? _sanitizeImageUrl(ogImage.trim())
        : article.imageUrl;

    final fullContent = paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : cleanSummary;

    return article.copyWith(
      title: cleanTitle,
      summary: cleanSummary,
      contentPlain: fullContent,
      imageUrl: cleanImage,
      imageUrls: cleanImage != null ? <String>[cleanImage] : article.imageUrls,
    );
  }

  static Map<String, dynamic>? _extractNewsArticleJson(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final type = decoded['@type']?.toString();
      if (type == 'NewsArticle' || decoded.containsKey('headline')) {
        return decoded;
      }
      if (decoded.containsKey('@graph') && decoded['@graph'] is List) {
        for (final item in decoded['@graph']) {
          if (item is Map<String, dynamic> &&
              (item['@type'] == 'NewsArticle' || item.containsKey('headline'))) {
            return item;
          }
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic> &&
            (item['@type'] == 'NewsArticle' || item.containsKey('headline'))) {
          return item;
        }
      }
    }
    return null;
  }

  static ArticleModel _buildFromNewsArticleJson(
    ArticleModel base,
    Map<String, dynamic> json,
  ) {
    final headline = json['headline']?.toString() ?? base.title;
    final articleBody = json['articleBody']?.toString() ?? '';
    final datePublishedStr = json['datePublished']?.toString();

    DateTime publishedAt = base.publishedAt;
    if (datePublishedStr != null) {
      try {
        final parsed = DateTime.parse(datePublishedStr);
        publishedAt = parsed.isUtc ? parsed : BoliviaDateFormatter.boliviaTimeToUtc(parsed);
      } catch (_) {}
    }

    String authorName = base.author;
    final authorRaw = json['author'];
    if (authorRaw is List && authorRaw.isNotEmpty && authorRaw.first is Map) {
      authorName = authorRaw.first['name']?.toString() ?? base.author;
    } else if (authorRaw is Map) {
      authorName = authorRaw['name']?.toString() ?? base.author;
    } else if (authorRaw is String && authorRaw.isNotEmpty) {
      authorName = authorRaw;
    }

    String? imageUrl = base.imageUrl;
    final imageRaw = json['image'];
    if (imageRaw is Map) {
      imageUrl = imageRaw['url']?.toString();
    } else if (imageRaw is String) {
      imageUrl = imageRaw;
    }
    if (imageUrl != null) {
      imageUrl = _sanitizeImageUrl(imageUrl);
    }

    final cleanSummary = articleBody.isNotEmpty
        ? (articleBody.length > 280 ? '${articleBody.substring(0, 277)}...' : articleBody)
        : base.summary;

    return base.copyWith(
      title: HtmlSanitizer.decodeHtmlEntities(headline),
      summary: HtmlSanitizer.decodeHtmlEntities(cleanSummary),
      contentPlain: articleBody.isNotEmpty ? HtmlSanitizer.decodeHtmlEntities(articleBody) : cleanSummary,
      author: HtmlSanitizer.decodeHtmlEntities(authorName),
      publishedAt: publishedAt,
      imageUrl: imageUrl,
      imageUrls: imageUrl != null ? <String>[imageUrl] : base.imageUrls,
    );
  }

  static String _sanitizeImageUrl(String url) {
    var clean = url.trim();
    // Corregir concatenaciones dobles de dominio (ej. https://unitel.bohttps://estaticos...)
    if (clean.contains('https://') && clean.indexOf('https://') != clean.lastIndexOf('https://')) {
      final lastIdx = clean.lastIndexOf('https://');
      clean = clean.substring(lastIdx);
    }
    return clean;
  }
}
