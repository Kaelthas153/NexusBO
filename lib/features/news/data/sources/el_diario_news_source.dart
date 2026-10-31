import 'dart:convert';

import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:xml/xml.dart';

/// Implementación de [NewsSource] para El Diario (Decano de la Prensa Nacional).
///
/// Consume exclusivamente el feed RSS 2.0 (`https://www.eldiario.net/portal/feed/`).
/// IMPORTANTE: No realiza solicitudes individuales secundarias a artículos HTML
/// para evitar bloqueos por CloudProxy/Sucuri (307 redirect con reto JS).
/// Todo el contenido, cuerpo y eventuales imágenes se extraen directamente del feed.
class ElDiarioNewsSource implements NewsSource {
  ElDiarioNewsSource({
    required DioClient dioClient,
    String feedUrl = ApiConstants.elDiarioFeedUrl,
  }) : _dioClient = dioClient,
       _feedUrl = feedUrl;

  final DioClient _dioClient;
  final String _feedUrl;

  @override
  String get id => ApiConstants.elDiarioSourceId; // 'eldiario'

  @override
  String get name => ApiConstants.elDiarioSourceName; // 'El Diario'

  @override
  int get sortOrder => 5;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawXml = await _dioClient.getRawString(
      _feedUrl,
      headers: const <String, Object>{
        'User-Agent': ApiConstants.browserUserAgent,
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
      },
    );
    return parseRssXml(rawXml);
  }

  /// Parsea el documento XML RSS 2.0 de El Diario.
  /// Expuesto públicamente para pruebas unitarias deterministas sin red.
  List<ArticleModel> parseRssXml(
    String rawXml, {
    DateTime? fetchedAtOverrideUtc,
  }) {
    final trimmed = rawXml.trim();
    if (trimmed.isEmpty) {
      throw const ParseException('El feed RSS de El Diario está vacío.');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } on XmlException catch (e) {
      throw ParseException(
        'El documento XML recibido de El Diario es inválido.',
        cause: e,
      );
    }

    final channelElement =
        document.getElement('rss')?.getElement('channel') ??
        document.getElement('channel');
    if (channelElement == null) {
      throw const ParseException(
        'El XML de El Diario no contiene un nodo <channel> RSS válido.',
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
        // Tolerante a ítems individuales con estructura anómala
      }
    }

    return List<ArticleModel>.unmodifiable(articles);
  }

  ArticleModel? _parseSingleItem(
    XmlElement item, {
    required DateTime fetchedAtUtc,
  }) {
    // 1. Enlace y URL canónica
    final rawLink =
        item.findElements('link').firstOrNull?.innerText.trim() ??
        item.findElements('guid').firstOrNull?.innerText.trim() ??
        '';
    if (rawLink.isEmpty) return null;
    final cleanUrl = _cleanUrl(rawLink);

    // 2. ID determinista basado en /portal/YYYY/MM/DD/slug/ o fallback estable
    final rawGuid = item.findElements('guid').firstOrNull?.innerText.trim();
    final id = _extractStableId(cleanUrl, rawGuid);

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

    // 6. Extracción de imágenes estrictamente desde content:encoded (cero segundas peticiones)
    final contentImages = HtmlSanitizer.extractAllImageUrls(rawContent);
    final String? resolvedImageUrl = contentImages.firstOrNull;
    final List<String> resolvedImageUrls = List<String>.unmodifiable(
      contentImages,
    );

    // 7. Autor desde dc:creator
    final rawAuthor =
        item.findElements('dc:creator').firstOrNull?.innerText.trim() ??
        item.findElements('creator').firstOrNull?.innerText.trim() ??
        item.findElements('author').firstOrNull?.innerText.trim();
    final author =
        (rawAuthor != null &&
            rawAuthor.isNotEmpty &&
            rawAuthor.toLowerCase() != 'none')
        ? HtmlSanitizer.decodeHtmlEntities(rawAuthor)
        : ApiConstants.elDiarioSourceName;

    // 8. Categorías y Tags
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

    // 9. Fecha de publicación RFC-822
    final rawPubDate = item
        .findElements('pubDate')
        .firstOrNull
        ?.innerText
        .trim();
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
      sourceId: ApiConstants.elDiarioSourceId,
      sourceName: ApiConstants.elDiarioSourceName,
      category: canonicalCategory,
      tags: tags,
      publishedAt: publishedAtUtc,
      fetchedAt: fetchedAtUtc,
    );
  }

  static String _extractStableId(String canonicalUrl, String? rawGuid) {
    // Formato habitual: https://www.eldiario.net/portal/YYYY/MM/DD/slug/
    final match = RegExp(
      r'/portal/(\d{4})/(\d{2})/(\d{2})/([^/]+)/?',
      caseSensitive: false,
    ).firstMatch(canonicalUrl);

    if (match != null) {
      final y = match.group(1)!;
      final m = match.group(2)!;
      final d = match.group(3)!;
      final slug = match
          .group(4)!
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
      if (slug.isNotEmpty) {
        return '${ApiConstants.elDiarioSourceId}_$y$m${d}_$slug';
      }
    }

    // Si el GUID tiene ?p=\d+
    if (rawGuid != null) {
      final pMatch = RegExp(r'[?&]p=(\d+)').firstMatch(rawGuid);
      if (pMatch != null) {
        return '${ApiConstants.elDiarioSourceId}_${pMatch.group(1)}';
      }
    }

    // Fallback determinista FNV-1a 64-bit sobre canonicalUrl (sin String.hashCode)
    final hashHex = _stableFnv1a64(canonicalUrl);
    return '${ApiConstants.elDiarioSourceId}_$hashHex';
  }

  static String _cleanUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return rawUrl.trim();
    return uri.removeFragment().toString();
  }

  /// Hash FNV-1a 64-bit determinista sin String.hashCode
  static String _stableFnv1a64(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
