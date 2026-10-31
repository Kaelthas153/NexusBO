import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:xml/xml.dart';

/// Implementación de [NewsSource] para el diario El País (Tarija).
///
/// Consume el Google News Sitemap XML oficial (`https://elpais.bo/sitemap-google-news.xml`).
/// Extrae título, fecha de publicación con zona horaria, keywords, imagen destacada
/// desde `<image:loc>` y realiza enriquecimiento controlado de cuerpo completo
/// únicamente para noticias nuevas sin degradar el rendimiento de sincronización.
class ElPaisNewsSource implements NewsSource {
  ElPaisNewsSource({
    required DioClient dioClient,
    NewsLocalDataSource? localDataSource,
    String sitemapUrl = ApiConstants.elPaisSitemapUrl,
    bool enrichNewArticles = true,
    int maxEnrichmentCount = 5,
  }) : _dioClient = dioClient,
       _localDataSource = localDataSource,
       _sitemapUrl = sitemapUrl,
       _enrichNewArticles = enrichNewArticles,
       _maxEnrichmentCount = maxEnrichmentCount;

  final DioClient _dioClient;
  final NewsLocalDataSource? _localDataSource;
  final String _sitemapUrl;
  final bool _enrichNewArticles;
  final int _maxEnrichmentCount;

  @override
  String get id => ApiConstants.elPaisSourceId; // 'elpais'

  @override
  String get name => ApiConstants.elPaisSourceName; // 'El País'

  @override
  int get sortOrder => 6;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawXml = await _dioClient.getRawString(
      _sitemapUrl,
      headers: const <String, Object>{
        'User-Agent': ApiConstants.browserUserAgent,
        'Accept': 'application/xml, text/xml, */*',
      },
    );

    final preliminary = parseSitemapXml(rawXml);
    if (preliminary.isEmpty) {
      return preliminary;
    }

    final enriched = <ArticleModel>[];
    var enrichmentAttempts = 0;

    for (final article in preliminary) {
      // 1. Si ya existe localmente con contenido completo, conservar versión enriquecida
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
          // Si falla la lectura local, continuar normalmente
        }
      }

      // 2. Enriquecimiento controlado para artículos nuevos (máximo N por ciclo)
      if (_enrichNewArticles && enrichmentAttempts < _maxEnrichmentCount) {
        enrichmentAttempts++;
        try {
          final pageHtml = await _dioClient.tryGetArticleHtml(
            article.url,
            headers: const <String, Object>{
              'User-Agent': ApiConstants.browserUserAgent,
              'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
            },
            timeout: const Duration(seconds: 4),
          );

          if (pageHtml != null && pageHtml.isNotEmpty) {
            final detailed = extractArticleDetailsFromHtml(pageHtml, baseArticle: article);
            enriched.add(detailed);
            continue;
          }
        } catch (_) {
          // Si falla la petición secundaria, se conserva el artículo base
        }
      }

      // 3. Si no se enriqueció o falló la petición, conservar la noticia base
      enriched.add(article);
    }

    return List<ArticleModel>.unmodifiable(enriched);
  }

  /// Parsea el sitemap XML de Google News de El País.
  /// Expuesto públicamente para pruebas unitarias deterministas sin red.
  List<ArticleModel> parseSitemapXml(
    String rawXml, {
    DateTime? fetchedAtOverrideUtc,
    Map<String, String>? articlePageHtmlByUrl,
  }) {
    final trimmed = rawXml.trim();
    if (trimmed.isEmpty) {
      throw const ParseException('El sitemap XML de El País está vacío.');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } on XmlException catch (e) {
      throw ParseException(
        'El documento XML recibido de El País es inválido.',
        cause: e,
      );
    }

    final urlElements = document.findAllElements('url');
    final fetchedAtUtc = (fetchedAtOverrideUtc ?? DateTime.now()).toUtc();
    final articles = <ArticleModel>[];

    for (final urlElement in urlElements) {
      try {
        final parsed = _parseSingleUrlElement(
          urlElement,
          fetchedAtUtc: fetchedAtUtc,
          articlePageHtmlByUrl: articlePageHtmlByUrl,
        );
        if (parsed != null) {
          articles.add(parsed);
        }
      } catch (_) {
        // Tolerante a entradas anómalas
      }
    }

    return List<ArticleModel>.unmodifiable(articles);
  }

  ArticleModel? _parseSingleUrlElement(
    XmlElement urlElement, {
    required DateTime fetchedAtUtc,
    Map<String, String>? articlePageHtmlByUrl,
  }) {
    // 1. Loc / URL del artículo
    final rawLoc = _findChildText(urlElement, 'loc');
    if (rawLoc == null || rawLoc.trim().isEmpty) return null;
    final cleanUrl = _cleanUrl(rawLoc);

    // 2. ID determinista basado en /{seccion}/{YYYYMMDD}_{slug}.html
    final id = _extractStableId(cleanUrl);

    // 3. Título desde <news:title> o fallback <loc>
    final rawTitle = _findChildText(urlElement, 'news:title') ??
        _findChildText(urlElement, 'title') ??
        '';
    final title = HtmlSanitizer.decodeHtmlEntities(rawTitle).trim();
    if (title.isEmpty) return null;

    // 4. Imagen destacada directamente desde <image:loc>
    final rawImageLoc = _findChildText(urlElement, 'image:loc') ??
        _findChildText(urlElement, 'loc', namespacePrefix: 'image');
    final imageUrl = (rawImageLoc != null && rawImageLoc.trim().isNotEmpty)
        ? rawImageLoc.trim()
        : null;
    final imageUrls = imageUrl != null ? <String>[imageUrl] : const <String>[];

    // 5. Categoría y Tags desde la sección de URL y <news:keywords>
    final rawKeywords = _findChildText(urlElement, 'news:keywords') ??
        _findChildText(urlElement, 'keywords') ??
        '';
    final tags = rawKeywords
        .split(',')
        .map((k) => HtmlSanitizer.decodeHtmlEntities(k).trim())
        .where((k) => k.isNotEmpty)
        .toList(growable: false);

    final urlSection = _extractSectionFromUrl(cleanUrl);
    final categoryCandidate = urlSection ?? tags.firstOrNull;
    final canonicalCategory = CategoryMapper.toCanonical(categoryCandidate);

    // 6. Fecha de publicación ISO-8601 con zona horaria (-04:00)
    final rawPubDate = _findChildText(urlElement, 'news:publication_date') ??
        _findChildText(urlElement, 'publication_date');
    final publishedAtUtc = (rawPubDate != null && rawPubDate.trim().isNotEmpty)
        ? (DateTime.tryParse(rawPubDate.trim())?.toUtc() ?? fetchedAtUtc)
        : fetchedAtUtc;

    // 7. Resumen preliminar (keywords o título)
    final summary = tags.isNotEmpty
        ? tags.join(' • ')
        : title;

    var baseArticle = ArticleModel(
      id: id,
      title: title,
      summary: summary,
      contentPlain: summary,
      url: cleanUrl,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      author: ApiConstants.elPaisSourceName,
      sourceId: ApiConstants.elPaisSourceId,
      sourceName: ApiConstants.elPaisSourceName,
      category: canonicalCategory,
      tags: tags.isNotEmpty
          ? tags
          : <String>[CategoryMapper.toDisplay(canonicalCategory)],
      publishedAt: publishedAtUtc,
      fetchedAt: fetchedAtUtc,
    );

    // Enriquecimiento síncrono para pruebas offline cuando se provee el mapa
    if (articlePageHtmlByUrl != null &&
        articlePageHtmlByUrl.containsKey(cleanUrl)) {
      final pageHtml = articlePageHtmlByUrl[cleanUrl]!;
      baseArticle = extractArticleDetailsFromHtml(pageHtml, baseArticle: baseArticle);
    }

    return baseArticle;
  }

  /// Extrae el cuerpo completo, autor y descripción OpenGraph del HTML semántico
  /// del artículo de El País sin selectores frágiles ni expresiones regulares para HTML.
  static ArticleModel extractArticleDetailsFromHtml(
    String pageHtml, {
    required ArticleModel baseArticle,
  }) {
    if (pageHtml.trim().isEmpty) return baseArticle;

    final document = html_parser.parse(pageHtml);

    // 1. Resumen desde <meta property="og:description">
    final ogDesc = document
            .querySelector('meta[property="og:description"]')
            ?.attributes['content'] ??
        document
            .querySelector('meta[name="description"]')
            ?.attributes['content'];
    final sanitizedSummary = (ogDesc != null && ogDesc.trim().isNotEmpty)
        ? HtmlSanitizer.decodeHtmlEntities(ogDesc).trim()
        : baseArticle.summary;

    // 2. Autor desde <meta name="author"> o fallback 'El País'
    final rawAuthor = document
            .querySelector('meta[name="author"]')
            ?.attributes['content'] ??
        document
            .querySelector('meta[property="article:author"]')
            ?.attributes['content'];
    final author = (rawAuthor != null && rawAuthor.trim().isNotEmpty)
        ? HtmlSanitizer.decodeHtmlEntities(rawAuthor).trim()
        : baseArticle.author;

    // 3. Contenedor semántico principal: <article id="ep_post_style"> o <article>
    final articleContainer = document.querySelector('article#ep_post_style') ??
        document.querySelector('article.uk-article') ??
        document.querySelector('article');

    final paragraphs = <String>[];
    final internalImages = <String>[...baseArticle.imageUrls];

    if (articleContainer != null) {
      final pElements = articleContainer.querySelectorAll('p');
      for (final p in pElements) {
        final text = HtmlSanitizer.decodeHtmlEntities(p.text).trim();
        if (text.isEmpty) continue;

        // Filtrar avisos de suscripción / muros de pago
        final lower = text.toLowerCase();
        if (lower.contains('acceso libre a') ||
            lower.contains('suscrip') ||
            lower.contains('suscrib') ||
            lower.contains('suscríb') ||
            lower.contains('prueba gratis') ||
            lower.contains('iniciar sesi')) {
          continue;
        }

        paragraphs.add(text);
      }

      // Extraer imágenes adicionales dentro del artículo
      final imgs = articleContainer.querySelectorAll('img');
      for (final img in imgs) {
        final src = img.attributes['src'] ?? img.attributes['data-src'];
        if (src != null && src.startsWith('http') && !internalImages.contains(src)) {
          internalImages.add(src);
        }
      }
    }

    final fullContent = paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : baseArticle.contentPlain;

    return baseArticle.copyWith(
      summary: sanitizedSummary,
      contentPlain: fullContent,
      author: author,
      imageUrls: internalImages,
    );
  }

  static String _extractStableId(String canonicalUrl) {
    // Formato habitual: https://elpais.bo/{seccion}/{YYYYMMDD}_{slug}.html
    final match = RegExp(
      r'/([a-zA-Z0-9_-]+)/(\d{8})_([^/.]+)\.html',
      caseSensitive: false,
    ).firstMatch(canonicalUrl);

    if (match != null) {
      final date = match.group(2)!;
      final rawSlug = match.group(3)!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
      if (rawSlug.isNotEmpty) {
        return '${ApiConstants.elPaisSourceId}_${date}_$rawSlug';
      }
    }

    // Fallback determinista FNV-1a 64-bit sobre la URL canónica
    final hashHex = _stableFnv1a64(canonicalUrl);
    return '${ApiConstants.elPaisSourceId}_$hashHex';
  }

  static String? _extractSectionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    return uri.pathSegments.first;
  }

  static String _cleanUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return rawUrl.trim();
    return uri.removeFragment().toString();
  }

  static String? _findChildText(
    XmlElement parent,
    String elementName, {
    String? namespacePrefix,
  }) {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.qualified == elementName || child.name.local == elementName) {
        return child.innerText;
      }
      if (namespacePrefix != null &&
          child.name.prefix == namespacePrefix &&
          child.name.local == elementName) {
        return child.innerText;
      }
    }

    // Búsqueda descendiente para nodos anidados como <news:news><news:title>
    for (final desc in parent.descendants.whereType<XmlElement>()) {
      if (desc.name.qualified == elementName || desc.name.local == elementName) {
        return desc.innerText;
      }
    }
    return null;
  }

  static String _stableFnv1a64(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
