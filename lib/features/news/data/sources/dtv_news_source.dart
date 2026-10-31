import 'dart:convert';

import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Implementación de [NewsSource] para DTV (Detrás de la Verdad).
///
/// Consume la API REST de WordPress pública (`https://dtv.bo/wp-json/wp/v2/posts?_embed&per_page=15`).
/// Extrae título, resumen, cuerpo completo, imagen destacada embebida, autor,
/// fecha UTC y categorías normalizadas en una sola petición HTTP sin descargas
/// secundarias.
class DtvNewsSource implements NewsSource {
  DtvNewsSource({
    required DioClient dioClient,
    String endpointUrl = defaultEndpointUrl,
  }) : _dioClient = dioClient,
       _endpointUrl = endpointUrl;

  final DioClient _dioClient;
  final String _endpointUrl;

  static const String defaultEndpointUrl =
      'https://dtv.bo/wp-json/wp/v2/posts?_embed&per_page=15';

  @override
  String get id => 'dtv';

  @override
  String get name => 'DTV';

  @override
  int get sortOrder => 2;

  /// Elimina de forma segura la marca de orden de bytes (BOM UTF-8 `\uFEFF`)
  /// que emite el servidor LiteSpeed de DTV al inicio del payload JSON.
  static String stripUtf8Bom(String raw) {
    if (raw.isNotEmpty && raw.codeUnitAt(0) == 0xFEFF) {
      return raw.substring(1);
    }
    return raw;
  }

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawText = await _dioClient.getRawString(
      _endpointUrl,
      headers: const <String, Object>{
        'Accept': 'application/json, text/plain, */*',
      },
    );
    return parseJsonPosts(rawText);
  }

  /// Parsea la respuesta JSON de WordPress REST API.
  /// Expuesto públicamente para pruebas unitarias deterministas con fixtures locales.
  List<ArticleModel> parseJsonPosts(
    String rawJson, {
    DateTime? fetchedAtOverrideUtc,
  }) {
    final cleaned = stripUtf8Bom(rawJson).trim();
    if (cleaned.isEmpty) {
      throw const ParseException('El payload JSON de DTV está vacío.');
    }

    final dynamic decoded;
    try {
      decoded = json.decode(cleaned);
    } catch (e) {
      throw ParseException(
        'Error al decodificar el JSON de DTV.',
        cause: e,
      );
    }

    if (decoded is! List) {
      throw const ParseException(
        'El payload de DTV no contiene una lista de publicaciones válida.',
      );
    }

    final fetchedAtUtc = (fetchedAtOverrideUtc ?? DateTime.now()).toUtc();
    final articles = <ArticleModel>[];

    for (final item in decoded) {
      if (item is! Map<String, dynamic> && item is! Map) continue;
      final post = Map<String, dynamic>.from(item as Map);

      try {
        final parsed = _parseSinglePost(post, fetchedAtUtc: fetchedAtUtc);
        if (parsed != null) {
          articles.add(parsed);
        }
      } catch (_) {
        // Tolerante a posts individuales con estructura corrupta
      }
    }

    return List<ArticleModel>.unmodifiable(articles);
  }

  ArticleModel? _parseSinglePost(
    Map<String, dynamic> post, {
    required DateTime fetchedAtUtc,
  }) {
    // 1. ID numérico
    final rawId = post['id'];
    if (rawId == null) return null;
    final id = 'dtv_$rawId';

    // 2. URL canónica limpia (remover parámetros utm de rastreo)
    final rawLink = (post['link'] as String?)?.trim() ?? '';
    if (rawLink.isEmpty) return null;
    final cleanUrl = _cleanUrl(rawLink);

    // 3. Título sanitizado
    final rawTitle = post['title'] is Map
        ? (post['title']['rendered'] as String? ?? '')
        : '';
    final title = HtmlSanitizer.decodeHtmlEntities(rawTitle).trim();
    if (title.isEmpty) return null;

    // 4. Contenido completo y resumen
    final rawContent = post['content'] is Map
        ? (post['content']['rendered'] as String? ?? '')
        : '';
    final contentPlain = HtmlSanitizer.sanitizeToPlainText(
      rawContent,
      preserveParagraphs: true,
    );

    final rawExcerpt = post['excerpt'] is Map
        ? (post['excerpt']['rendered'] as String? ?? '')
        : '';
    final summaryFromExcerpt = HtmlSanitizer.sanitizeToPlainText(
      rawExcerpt,
      preserveParagraphs: false,
    );

    final summary = summaryFromExcerpt.isNotEmpty
        ? summaryFromExcerpt
        : (contentPlain.isNotEmpty ? _truncateSummary(contentPlain) : title);

    // 5. Metadatos embebidos (_embedded)
    final embedded = post['_embedded'] is Map
        ? Map<String, dynamic>.from(post['_embedded'] as Map)
        : const <String, dynamic>{};

    // 6. Imagen destacada + imágenes internas
    final featuredImageUrl = _extractFeaturedImageUrl(embedded);
    final contentImages = HtmlSanitizer.extractAllImageUrls(rawContent);

    final mergedImages = <String>[];
    if (featuredImageUrl != null && featuredImageUrl.isNotEmpty) {
      mergedImages.add(featuredImageUrl);
    }
    for (final img in contentImages) {
      if (!mergedImages.contains(img)) {
        mergedImages.add(img);
      }
    }

    final mainImageUrl = mergedImages.isNotEmpty ? mergedImages.first : null;

    // 7. Autor
    final author = _extractAuthor(embedded);

    // 8. Categorías y etiquetas
    final (:canonicalCategory, :tags) = _extractCategoriesAndTags(embedded);

    // 9. Fecha de publicación
    final publishedAtUtc = _parseDate(
      post['date_gmt'],
      post['date'],
      fallbackUtc: fetchedAtUtc,
    );

    return ArticleModel(
      id: id,
      title: title,
      summary: summary,
      contentPlain: contentPlain.isNotEmpty ? contentPlain : summary,
      url: cleanUrl,
      imageUrl: mainImageUrl,
      imageUrls: mergedImages,
      author: author,
      sourceId: this.id, // 'dtv'
      sourceName: name, // 'DTV'
      category: canonicalCategory,
      tags: tags,
      publishedAt: publishedAtUtc,
      fetchedAt: fetchedAtUtc,
    );
  }

  static String? _extractFeaturedImageUrl(Map<String, dynamic> embedded) {
    final mediaList = embedded['wp:featuredmedia'];
    if (mediaList is List && mediaList.isNotEmpty) {
      final firstMedia = mediaList.first;
      if (firstMedia is Map) {
        final sourceUrl = firstMedia['source_url'] as String?;
        if (sourceUrl != null && sourceUrl.trim().isNotEmpty) {
          return sourceUrl.trim();
        }
      }
    }
    return null;
  }

  static String _extractAuthor(Map<String, dynamic> embedded) {
    final authorList = embedded['author'];
    if (authorList is List && authorList.isNotEmpty) {
      final firstAuthor = authorList.first;
      if (firstAuthor is Map) {
        final name = (firstAuthor['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          return HtmlSanitizer.decodeHtmlEntities(name);
        }
      }
    }
    return 'DTV';
  }

  static ({String canonicalCategory, List<String> tags})
      _extractCategoriesAndTags(Map<String, dynamic> embedded) {
    final termsList = embedded['wp:term'];
    final categoryNames = <String>[];
    final allTags = <String>[];

    if (termsList is List) {
      for (final termGroup in termsList) {
        if (termGroup is! List) continue;
        for (final term in termGroup) {
          if (term is! Map) continue;
          final name = (term['name'] as String?)?.trim();
          final taxonomy = term['taxonomy'] as String?;
          if (name == null || name.isEmpty) continue;

          final cleanName = HtmlSanitizer.decodeHtmlEntities(name);
          allTags.add(cleanName);

          if (taxonomy == 'category') {
            categoryNames.add(cleanName);
          }
        }
      }
    }

    final rawCategory =
        categoryNames.isNotEmpty ? categoryNames.first : 'General';
    final canonical = CategoryMapper.toCanonical(rawCategory);

    return (
      canonicalCategory: canonical,
      tags: List<String>.unmodifiable(allTags),
    );
  }

  static DateTime _parseDate(
    dynamic dateGmt,
    dynamic dateRaw, {
    required DateTime fallbackUtc,
  }) {
    if (dateGmt is String && dateGmt.trim().isNotEmpty) {
      var s = dateGmt.trim();
      if (!s.endsWith('Z')) s = '${s}Z';
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed.toUtc();
    }
    if (dateRaw is String && dateRaw.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(dateRaw.trim());
      if (parsed != null) return parsed.toUtc();
    }
    return fallbackUtc;
  }

  static String _cleanUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return rawUrl.trim();
    final cleanParams = Map<String, String>.from(uri.queryParameters)
      ..removeWhere(
        (key, _) =>
            key.startsWith('utm_') || key == 'fbclid' || key == 'ref',
      );
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: cleanParams.isEmpty ? null : cleanParams,
    ).toString();
  }

  static String _truncateSummary(String text, {int maxChars = 280}) {
    if (text.length <= maxChars) return text;
    final slice = text.substring(0, maxChars);
    final lastSpace = slice.lastIndexOf(' ');
    if (lastSpace > 0) {
      return '${slice.substring(0, lastSpace)}…';
    }
    return '$slice…';
  }
}
