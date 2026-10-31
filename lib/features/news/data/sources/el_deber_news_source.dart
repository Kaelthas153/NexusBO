import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Implementación de [NewsSource] para El Deber (Santa Cruz de la Sierra).
///
/// Consume el feed RSS 2.0 oficial (`https://eldeber.com.bo/feed/`).
/// Extrae la imagen destacada directamente del nodo `<enclosure>`, deduce el ID
/// numérico único de la URL y mapea la categoría temática desde el path del enlace.
class ElDeberNewsSource implements NewsSource {
  ElDeberNewsSource({
    required DioClient dioClient,
    String feedUrl = defaultFeedUrl,
  }) : _dioClient = dioClient,
       _feedUrl = feedUrl;

  final DioClient _dioClient;
  final String _feedUrl;

  static const String defaultFeedUrl = 'https://eldeber.com.bo/feed/';

  @override
  String get id => 'eldeber';

  @override
  String get name => 'El Deber';

  @override
  int get sortOrder => 3;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawXml = await _dioClient.getRawString(
      _feedUrl,
      headers: const <String, Object>{
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
      },
    );
    return parseRssXml(rawXml);
  }

  /// Parsea el documento XML RSS 2.0 de El Deber.
  /// Expuesto públicamente para pruebas unitarias deterministas sin red.
  List<ArticleModel> parseRssXml(
    String rawXml, {
    DateTime? fetchedAtOverrideUtc,
  }) {
    final trimmed = rawXml.trim();
    if (trimmed.isEmpty) {
      throw const ParseException('El feed RSS de El Deber está vacío.');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } on XmlException catch (e) {
      throw ParseException(
        'El documento XML recibido de El Deber es inválido.',
        cause: e,
      );
    }

    final channelElement =
        document.getElement('rss')?.getElement('channel') ??
        document.getElement('channel');
    if (channelElement == null) {
      throw const ParseException(
        'El XML de El Deber no contiene un nodo <channel> RSS válido.',
      );
    }

    final itemElements = channelElement.findElements('item');
    final fetchedAtUtc = (fetchedAtOverrideUtc ?? DateTime.now()).toUtc();
    final articles = <ArticleModel>[];

    for (final item in itemElements) {
      try {
        final parsed = _parseSingleItem(item, fetchedAtUtc: fetchedAtUtc);
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
  }) {
    // 1. Enlace y URL canónica
    final rawLink = item.findElements('link').firstOrNull?.innerText.trim() ??
        item.findElements('guid').firstOrNull?.innerText.trim() ??
        '';
    if (rawLink.isEmpty) return null;
    final cleanUrl = _cleanUrl(rawLink);

    // 2. ID determinista
    final id = _extractStableId(cleanUrl);

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

    // 5. Imagen desde <enclosure>
    final enclosureImageUrl = _extractEnclosureImageUrl(item);
    final imageUrls = enclosureImageUrl != null && enclosureImageUrl.isNotEmpty
        ? <String>[enclosureImageUrl]
        : const <String>[];

    // 6. Autor (fallback a 'EL DEBER' para evitar 'None' o 'null')
    final rawAuthor =
        item.findElements('author').firstOrNull?.innerText.trim() ??
        item.findElements('dc:creator').firstOrNull?.innerText.trim();
    final author = (rawAuthor != null &&
            rawAuthor.isNotEmpty &&
            rawAuthor.toLowerCase() != 'none' &&
            rawAuthor.toLowerCase() != 'null')
        ? HtmlSanitizer.decodeHtmlEntities(rawAuthor)
        : 'EL DEBER';

    // 7. Categoría deducida de la URL y mapeada canónicamente
    final (:canonicalCategory, :tags) = _extractCategoryAndTags(item, cleanUrl);

    // 8. Fecha de publicación RFC-822
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
      contentPlain: finalSummary,
      url: cleanUrl,
      imageUrl: enclosureImageUrl,
      imageUrls: imageUrls,
      author: author,
      sourceId: this.id, // 'eldeber'
      sourceName: name, // 'El Deber'
      category: canonicalCategory,
      tags: tags,
      publishedAt: publishedAtUtc,
      fetchedAt: fetchedAtUtc,
    );
  }

  /// Extrae el ID de 10 dígitos ubicado al final de las URLs de El Deber
  /// (e.g. `..._1793447811` -> `eldeber_1793447811`).
  /// Si la URL no contiene ese sufijo, genera un hash FNV-1a determinista de la URL.
  static String _extractStableId(String url) {
    // Las notas de El Deber incluyen un identificador numérico precedido por guion bajo
    // e.g. https://eldeber.com.bo/pais/..._1793447811
    final matches = RegExp(r'_(\d{4,})').allMatches(url);
    if (matches.isNotEmpty) {
      return 'eldeber_${matches.last.group(1)}';
    }

    // Fallback determinista (nunca String.hashCode)
    var hash = 0x811c9dc5;
    for (final b in utf8.encode(url)) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'eldeber_${hash.toRadixString(16)}';
  }

  static String? _extractEnclosureImageUrl(XmlElement item) {
    for (final enclosure in item.findElements('enclosure')) {
      final url = enclosure.getAttribute('url')?.trim();
      final type = enclosure.getAttribute('type')?.toLowerCase() ?? '';
      if (url != null && url.isNotEmpty) {
        if (type.startsWith('image/') ||
            url.contains('.jpg') ||
            url.contains('.jpeg') ||
            url.contains('.png') ||
            url.contains('.webp')) {
          return url;
        }
      }
    }
    return null;
  }

  static ({String canonicalCategory, List<String> tags}) _extractCategoryAndTags(
    XmlElement item,
    String url,
  ) {
    final tags = <String>[];
    for (final cat in item.findElements('category')) {
      final text = HtmlSanitizer.decodeHtmlEntities(cat.innerText).trim();
      if (text.isNotEmpty) tags.add(text);
    }

    // Deducir categoría primaria a partir del segmento de la URL
    // e.g. https://eldeber.com.bo/pais/... -> 'pais' -> 'sociedad'
    final uri = Uri.tryParse(url);
    String rawCategorySegment = 'general';
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final firstSegment = uri.pathSegments.first.trim().toLowerCase();
      if (firstSegment.isNotEmpty && !firstSegment.startsWith('noticia')) {
        rawCategorySegment = firstSegment;
      }
    }

    final candidate = tags.isNotEmpty ? tags.first : rawCategorySegment;
    final canonical = CategoryMapper.toCanonical(candidate);

    return (
      canonicalCategory: canonical,
      tags: List<String>.unmodifiable(tags),
    );
  }

  static String _cleanUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (!trimmed.contains('?')) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    final cleanParams = Map<String, String>.from(uri.queryParameters)
      ..removeWhere(
        (key, _) =>
            key.startsWith('utm_') || key == 'fbclid' || key == 'ref',
      );
    return uri.replace(
      queryParameters: cleanParams.isEmpty ? null : cleanParams,
      fragment: '',
    ).toString();
  }
}
