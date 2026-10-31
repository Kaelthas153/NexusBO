import 'dart:convert';

import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/datasources/news_local_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:xml/xml.dart';

/// Implementación de [NewsSource] para el diario La Razón (La Paz).
///
/// Consume el feed RSS 2.0 oficial (`https://larazon.bo/feed/`).
/// Utiliza un User-Agent de navegación estándar para evitar respuestas 403
/// de Cloudflare, extrae el cuerpo completo desde `content:encoded` y
/// enriquece imágenes destacadas vía `og:image` de forma condicional únicamente
/// cuando no existen imágenes en el contenido y el artículo no está en caché.
class LaRazonNewsSource implements NewsSource {
  LaRazonNewsSource({
    required DioClient dioClient,
    NewsLocalDataSource? localDataSource,
    String feedUrl = ApiConstants.laRazonFeedUrl,
    bool resolveFeaturedImages = true,
  }) : _dioClient = dioClient,
       _localDataSource = localDataSource,
       _feedUrl = feedUrl,
       _resolveFeaturedImages = resolveFeaturedImages;

  final DioClient _dioClient;
  final NewsLocalDataSource? _localDataSource;
  final String _feedUrl;
  final bool _resolveFeaturedImages;

  @override
  String get id => ApiConstants.laRazonSourceId; // 'larazon'

  @override
  String get name => ApiConstants.laRazonSourceName; // 'La Razón'

  @override
  int get sortOrder => 4;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawXml = await _dioClient.getRawString(
      _feedUrl,
      headers: const <String, Object>{
        'User-Agent': ApiConstants.browserUserAgent,
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
      },
    );

    final preliminary = parseRssXml(rawXml);
    if (!_resolveFeaturedImages || preliminary.isEmpty) {
      return preliminary;
    }

    final enriched = <ArticleModel>[];
    for (final article in preliminary) {
      // 1. Si ya tiene imagen extraída del contenido, no requiere enriquecimiento
      if (article.imageUrl != null && article.imageUrl!.isNotEmpty) {
        enriched.add(article);
        continue;
      }

      // 2. Si ya existe en SQLite local con imagen válida, preservar la existente
      if (_localDataSource != null) {
        try {
          final cached = await _localDataSource.getArticleById(article.id);
          if (cached != null &&
              cached.imageUrl != null &&
              cached.imageUrl!.isNotEmpty) {
            enriched.add(
              article.copyWith(
                imageUrl: cached.imageUrl,
                imageUrls: cached.imageUrls,
              ),
            );
            continue;
          }
        } catch (_) {
          // Si falla la consulta local, continuar con la estrategia regular
        }
      }

      // 3. Segunda petición condicional: consultar el HTML del artículo para og:image
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
          final ogImage =
              HtmlSanitizer.extractFeaturedImageFromArticleHtml(pageHtml);
          if (ogImage != null && ogImage.isNotEmpty) {
            enriched.add(
              article.copyWith(
                imageUrl: ogImage,
                imageUrls: <String>[ogImage],
              ),
            );
            continue;
          }
        }
      } catch (_) {
        // Un fallo de imagen jamás descarta el artículo
      }

      // 4. Si no se obtuvo imagen o falló la petición, conservar noticia sin imagen
      enriched.add(article);
    }

    return List<ArticleModel>.unmodifiable(enriched);
  }

  /// Parsea el documento XML RSS 2.0 de La Razón.
  /// Expuesto públicamente para pruebas unitarias deterministas sin red.
  List<ArticleModel> parseRssXml(
    String rawXml, {
    DateTime? fetchedAtOverrideUtc,
    Map<String, String>? articlePageHtmlByUrl,
  }) {
    final trimmed = rawXml.trim();
    if (trimmed.isEmpty) {
      throw const ParseException('El feed RSS de La Razón está vacío.');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } on XmlException catch (e) {
      throw ParseException(
        'El documento XML recibido de La Razón es inválido.',
        cause: e,
      );
    }

    final channelElement =
        document.getElement('rss')?.getElement('channel') ??
        document.getElement('channel');
    if (channelElement == null) {
      throw const ParseException(
        'El XML de La Razón no contiene un nodo <channel> RSS válido.',
      );
    }

    final itemElements = channelElement.findElements('item');
    final fetchedAtUtc = (fetchedAtOverrideUtc ?? DateTime.now()).toUtc();
    final articles = <ArticleModel>[];

    for (final item in itemElements) {
      try {
        final parsed = _parseSingleItem(
          item,
          fetchedAtUtc: fetchedAtUtc,
          articlePageHtmlByUrl: articlePageHtmlByUrl,
        );
        if (parsed != null) {
          articles.add(parsed);
        }
      } catch (_) {
        // Tolerante a ítems individuales con tags anómalos
      }
    }

    return List<ArticleModel>.unmodifiable(articles);
  }

  ArticleModel? _parseSingleItem(
    XmlElement item, {
    required DateTime fetchedAtUtc,
    Map<String, String>? articlePageHtmlByUrl,
  }) {
    // 1. Enlace y URL canónica
    final rawLink = item.findElements('link').firstOrNull?.innerText.trim() ??
        item.findElements('guid').firstOrNull?.innerText.trim() ??
        '';
    if (rawLink.isEmpty) return null;
    final cleanUrl = _cleanUrl(rawLink);

    // 2. ID determinista basado en GUID (?p=123) o fallback estable
    final rawGuid = item.findElements('guid').firstOrNull?.innerText.trim();
    final id = _extractStableId(rawGuid, cleanUrl);

    // 3. Título
    final rawTitle = item.findElements('title').firstOrNull?.innerText ?? '';
    final title = HtmlSanitizer.decodeHtmlEntities(rawTitle).trim();
    if (title.isEmpty) return null;

    // 4. Resumen / Descripción
    final rawDescription =
        item.findElements('description').firstOrNull?.innerText ?? '';
    final summary = HtmlSanitizer.sanitizeToPlainText(
      rawDescription,
      preserveParagraphs: false,
    );
    final finalSummary = summary.isNotEmpty ? summary : title;

    // 5. Cuerpo completo desde content:encoded
    final rawContent =
        item.findElements('content:encoded').firstOrNull?.innerText ??
        item.findElements('encoded').firstOrNull?.innerText ??
        '';
    final contentPlain = HtmlSanitizer.sanitizeToPlainText(
      rawContent,
      preserveParagraphs: true,
    );

    // 6. Extracción de imágenes desde content:encoded
    final contentImages = HtmlSanitizer.extractAllImageUrls(rawContent);
    String? resolvedImageUrl = contentImages.firstOrNull;
    List<String> resolvedImageUrls = List<String>.unmodifiable(contentImages);

    // 7. Enriquecimiento síncrono para pruebas (cuando se pasa fixture de página HTML)
    if (resolvedImageUrl == null &&
        articlePageHtmlByUrl != null &&
        articlePageHtmlByUrl.containsKey(cleanUrl)) {
      final pageHtml = articlePageHtmlByUrl[cleanUrl];
      final ogImage =
          HtmlSanitizer.extractFeaturedImageFromArticleHtml(pageHtml);
      if (ogImage != null && ogImage.isNotEmpty) {
        resolvedImageUrl = ogImage;
        resolvedImageUrls = <String>[ogImage];
      }
    }

    // 8. Autor desde dc:creator
    final rawAuthor =
        item.findElements('dc:creator').firstOrNull?.innerText.trim() ??
        item.findElements('creator').firstOrNull?.innerText.trim() ??
        item.findElements('author').firstOrNull?.innerText.trim();
    final author = (rawAuthor != null &&
            rawAuthor.isNotEmpty &&
            rawAuthor.toLowerCase() != 'none')
        ? HtmlSanitizer.decodeHtmlEntities(rawAuthor)
        : ApiConstants.laRazonSourceName;

    // 9. Categorías y Tags
    final rawCategories = item
        .findElements('category')
        .map((e) => HtmlSanitizer.decodeHtmlEntities(e.innerText).trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final primaryCategory = rawCategories.firstOrNull;
    final canonicalCategory = CategoryMapper.toCanonical(primaryCategory);
    final tags = rawCategories.isNotEmpty
        ? rawCategories
        : <String>[CategoryMapper.toDisplay(canonicalCategory)];

    // 10. Fecha de publicación RFC-822
    final rawPubDate =
        item.findElements('pubDate').firstOrNull?.innerText.trim();
    final publishedAtUtc = rawPubDate != null && rawPubDate.isNotEmpty
        ? BoliviaDateFormatter.parseRssRfc822Utc(
            rawPubDate,
            fallbackUtc: fetchedAtUtc,
          )
        : fetchedAtUtc;

    return ArticleModel(
      id: id,
      title: title,
      summary: finalSummary,
      contentPlain: contentPlain.isNotEmpty ? contentPlain : finalSummary,
      url: cleanUrl,
      imageUrl: resolvedImageUrl,
      imageUrls: resolvedImageUrls,
      author: author,
      sourceId: _idPrefix,
      sourceName: ApiConstants.laRazonSourceName,
      category: canonicalCategory,
      tags: tags,
      publishedAt: publishedAtUtc,
      fetchedAt: fetchedAtUtc,
    );
  }

  static const String _idPrefix = ApiConstants.laRazonSourceId;

  static String _extractStableId(String? rawGuid, String canonicalUrl) {
    if (rawGuid != null && rawGuid.isNotEmpty) {
      final pMatch = RegExp(r'[?&]p=(\d+)').firstMatch(rawGuid);
      if (pMatch != null) {
        return '${_idPrefix}_${pMatch.group(1)}';
      }
    }

    // Si la URL canónica tiene ?p=\d+
    final urlPMatch = RegExp(r'[?&]p=(\d+)').firstMatch(canonicalUrl);
    if (urlPMatch != null) {
      return '${_idPrefix}_${urlPMatch.group(1)}';
    }

    // Fallback determinista basado en FNV-1a 64-bit sobre la URL canónica (sin String.hashCode)
    final hashHex = _stableFnv1a64(canonicalUrl);
    return '${_idPrefix}_$hashHex';
  }

  static String _cleanUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return rawUrl.trim();
    return uri.removeFragment().toString();
  }

  /// Hash FNV-1a de 64 bits estable y determinista en todas las plataformas y ejecuciones.
  static String _stableFnv1a64(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
