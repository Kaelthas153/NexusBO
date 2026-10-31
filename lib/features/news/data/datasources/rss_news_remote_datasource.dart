import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/errors/app_exception.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/utils/html_sanitizer.dart';
import 'package:nexusbo/features/news/data/datasources/news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';

/// Implementación RSS de [NewsRemoteDataSource] para la Agencia Boliviana de
/// Información (`https://abi.bo/feed/`).
class RssNewsRemoteDataSource implements NewsRemoteDataSource {
  RssNewsRemoteDataSource({
    required DioClient dioClient,
    String feedUrl = ApiConstants.abiFeedUrl,
    this.resolveFeaturedImagesFromArticlePages = true,
  }) : _dioClient = dioClient,
       _feedUrl = feedUrl;

  final DioClient _dioClient;
  final String _feedUrl;

  /// Si es `true`, cuando un `<item>` del RSS no incluye imagen destacada
  /// explícita (`media:content` / `enclosure`), consulta de forma tolerante a
  /// fallos la página del artículo para obtener su `og:image` / `wp-post-image`.
  final bool resolveFeaturedImagesFromArticlePages;

  static const String _contentNs = 'http://purl.org/rss/1.0/modules/content/';
  static const String _dcNs = 'http://purl.org/dc/elements/1.1/';
  static const String _mediaNs = 'http://search.yahoo.com/mrss/';

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawXml = await _dioClient.getRawXml(_feedUrl);
    final parsedEntries = _parseRssItemsInternal(rawXml);

    if (!resolveFeaturedImagesFromArticlePages || parsedEntries.isEmpty) {
      return parsedEntries.map((e) => e.model).toList(growable: false);
    }

    // Resolver en paralelo las imágenes destacadas (og:image / wp-post-image)
    // de las páginas de artículos cuando el RSS no entregó imagen directa.
    return Future.wait(
      parsedEntries.map((entry) async {
        if (entry.hasDirectRssFeaturedImage) {
          return entry.model;
        }

        final pageHtml = await _dioClient.tryGetArticleHtml(entry.model.url);
        final pageFeaturedUrl =
            HtmlSanitizer.extractFeaturedImageFromArticleHtml(pageHtml);

        if (pageFeaturedUrl == null) {
          return entry.model;
        }

        // Combinar: 1º imagen destacada de la página (og:image / wp-post-image),
        // seguida de todas las imágenes válidas dentro de content:encoded.
        final mergedImages = mergeUniqueImageUrls(<String>[
          pageFeaturedUrl,
          ...entry.contentImageUrls,
        ]);

        return entry.model.copyWith(
          imageUrl: mergedImages.first,
          imageUrls: mergedImages,
        );
      }),
    );
  }

  /// Parsea el documento XML RSS 2.0 y transforma cada `<item>` válido en un
  /// [ArticleModel].
  ///
  /// Expuesto públicamente para pruebas unitarias deterministas con fixtures
  /// XML locales (y opcionalmente un mapa `articlePageHtmlByUrl` para simular
  /// páginas de artículos con `og:image` sin conexión a Internet).
  List<ArticleModel> parseRssXml(
    String rawXml, {
    DateTime? fetchedAtOverrideUtc,
    Map<String, String>? articlePageHtmlByUrl,
  }) {
    final entries = _parseRssItemsInternal(
      rawXml,
      fetchedAtOverrideUtc: fetchedAtOverrideUtc,
    );

    if (articlePageHtmlByUrl == null || articlePageHtmlByUrl.isEmpty) {
      return entries.map((e) => e.model).toList(growable: false);
    }

    return entries.map((entry) {
      if (entry.hasDirectRssFeaturedImage) {
        return entry.model;
      }
      final pageHtml = articlePageHtmlByUrl[entry.model.url];
      final pageFeaturedUrl = HtmlSanitizer.extractFeaturedImageFromArticleHtml(
        pageHtml,
      );
      if (pageFeaturedUrl == null) {
        return entry.model;
      }
      final merged = mergeUniqueImageUrls(<String>[
        pageFeaturedUrl,
        ...entry.contentImageUrls,
      ]);
      return entry.model.copyWith(
        imageUrl: merged.first,
        imageUrls: merged,
      );
    }).toList(growable: false);
  }

  List<_ParsedRssEntry> _parseRssItemsInternal(
    String rawXml, {
    DateTime? fetchedAtOverrideUtc,
  }) {
    final trimmed = rawXml.trim();
    if (trimmed.isEmpty) {
      throw const ParseException('El documento RSS está vacío.');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } on XmlException catch (e) {
      throw ParseException(
        'El documento XML recibido de ABI es inválido.',
        cause: e,
      );
    }

    final rssElement = document.getElement('rss');
    final channelElement =
        rssElement?.getElement('channel') ?? document.getElement('channel');
    if (channelElement == null) {
      throw const ParseException(
        'El XML no contiene un nodo <channel> RSS válido.',
      );
    }

    final itemElements = channelElement.findElements('item');
    final fetchedAtUtc = (fetchedAtOverrideUtc ?? DateTime.now()).toUtc();

    final entries = <_ParsedRssEntry>[];
    for (final item in itemElements) {
      try {
        final parsed = _parseSingleItem(item, fetchedAtUtc: fetchedAtUtc);
        if (parsed != null) {
          entries.add(parsed);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RssNewsRemoteDataSource] Item defectuoso omitido: $e');
        }
      }
    }

    return entries;
  }

  _ParsedRssEntry? _parseSingleItem(
    XmlElement item, {
    required DateTime fetchedAtUtc,
  }) {
    // 1. Título
    final rawTitle = _readElementText(item, 'title');
    final title = HtmlSanitizer.sanitizeToPlainText(
      HtmlSanitizer.decodeHtmlEntities(rawTitle ?? ''),
      preserveParagraphs: false,
    ).trim();
    if (title.isEmpty) {
      return null;
    }

    // 2. Link y GUID -> ID determinista
    final rawLink = _readElementText(item, 'link');
    final normalizedLink = _normalizeAbiUrl(rawLink);
    final rawGuid = _readElementText(item, 'guid');

    final id = extractDeterministicId(
      rawGuid: rawGuid,
      canonicalUrl: normalizedLink,
    );
    if (id == null || id.isEmpty) {
      return null;
    }

    final url = normalizedLink.isNotEmpty
        ? normalizedLink
        : _normalizeAbiUrl(rawGuid);
    if (url.isEmpty) {
      return null;
    }

    // 3. Contenido y Resumen
    final rawContentEncoded = _readNamespacedElementText(
      item,
      localName: 'encoded',
      namespaceUri: _contentNs,
      qualifiedFallback: 'content:encoded',
    );
    final rawDescription = _readElementText(item, 'description');

    final contentFromEncoded = rawContentEncoded != null
        ? HtmlSanitizer.sanitizeToPlainText(
            rawContentEncoded,
            preserveParagraphs: true,
          )
        : '';
    final contentFromDescription = rawDescription != null
        ? HtmlSanitizer.sanitizeToPlainText(
            rawDescription,
            preserveParagraphs: true,
          )
        : '';

    final contentPlain = contentFromEncoded.isNotEmpty
        ? contentFromEncoded
        : contentFromDescription;

    final summaryFromDescription = rawDescription != null
        ? HtmlSanitizer.sanitizeToPlainText(
            rawDescription,
            preserveParagraphs: false,
          )
        : '';

    final summary = _resolveSummary(
      summaryFromDescription: summaryFromDescription,
      contentPlain: contentPlain,
      fallbackTitle: title,
    );

    // 4. Imágenes (RSS directa + todas las imágenes de content:encoded / description)
    final directRssImage = _extractDirectRssImageUrl(item);
    final contentImages = mergeUniqueImageUrls(<String>[
      ...HtmlSanitizer.extractAllImageUrls(rawContentEncoded),
      ...HtmlSanitizer.extractAllImageUrls(rawDescription),
    ]);

    final allInitialImages = mergeUniqueImageUrls(<String>[
      if (directRssImage != null) directRssImage,
      ...contentImages,
    ]);

    final mainImageUrl = allInitialImages.isNotEmpty
        ? allInitialImages.first
        : null;

    // 5. Autor (dc:creator)
    final rawCreator = _readNamespacedElementText(
      item,
      localName: 'creator',
      namespaceUri: _dcNs,
      qualifiedFallback: 'dc:creator',
    );
    final cleanedAuthor = HtmlSanitizer.decodeHtmlEntities(
      rawCreator ?? '',
    ).trim();
    final author = cleanedAuthor.isNotEmpty
        ? cleanedAuthor
        : ApiConstants.defaultAuthorFallback;

    // 6. Categorías y Tags
    final (:category, :tags) = _extractCategoryAndTags(item);

    // 7. Fecha de publicación (UTC)
    final rawPubDate = _readElementText(item, 'pubDate');
    final publishedAtUtc = rawPubDate != null && rawPubDate.trim().isNotEmpty
        ? BoliviaDateFormatter.parseRssRfc822Utc(
            rawPubDate,
            fallbackUtc: fetchedAtUtc,
          )
        : fetchedAtUtc;

    final model = ArticleModel(
      id: id,
      title: title,
      summary: summary,
      contentPlain: contentPlain.isNotEmpty ? contentPlain : summary,
      url: url,
      imageUrl: mainImageUrl,
      imageUrls: allInitialImages,
      author: author,
      sourceId: ApiConstants.abiSourceId,
      sourceName: ApiConstants.abiSourceName,
      category: category,
      tags: tags,
      publishedAt: publishedAtUtc,
      fetchedAt: fetchedAtUtc,
      isFavorite: false,
      favoritedAt: null,
      isRead: false,
    );

    return _ParsedRssEntry(
      model: model,
      hasDirectRssFeaturedImage: directRssImage != null,
      contentImageUrls: contentImages,
    );
  }

  /// Combina y deduplica una lista de URLs de imagen comparando su clave
  /// canónica (evitando duplicar versiones `-WxH` de la misma foto en WordPress).
  static List<String> mergeUniqueImageUrls(Iterable<String> urls) {
    final results = <String>[];
    final seenCanonicalKeys = <String>{};

    for (final raw in urls) {
      final normalized = _normalizeImageUrl(raw);
      if (normalized == null) continue;
      final key = HtmlSanitizer.canonicalImageKey(normalized);
      if (seenCanonicalKeys.add(key)) {
        results.add(normalized);
      }
    }
    return results;
  }

  /// Genera un identificador determinista estable a partir de `<guid>` o `<link>`:
  /// - Si `<guid>` contiene el parámetro `?p=41195`, devuelve `'abi_41195'`.
  /// - De lo contrario, utiliza el contenido normalizado de `<guid>`.
  /// - Si no existe `<guid>`, utiliza la URL canónica normalizada.
  static String? extractDeterministicId({
    required String? rawGuid,
    required String? canonicalUrl,
  }) {
    final trimmedGuid = rawGuid?.trim() ?? '';
    if (trimmedGuid.isNotEmpty) {
      final uri = Uri.tryParse(trimmedGuid);
      final postId = uri?.queryParameters['p']?.trim();
      if (postId != null &&
          postId.isNotEmpty &&
          RegExp(r'^\d+$').hasMatch(postId)) {
        return '${ApiConstants.abiSourceId}_$postId';
      }
      return _normalizeAbiUrl(trimmedGuid);
    }

    final trimmedUrl = canonicalUrl?.trim() ?? '';
    if (trimmedUrl.isNotEmpty) {
      final uri = Uri.tryParse(trimmedUrl);
      final postId = uri?.queryParameters['p']?.trim();
      if (postId != null &&
          postId.isNotEmpty &&
          RegExp(r'^\d+$').hasMatch(postId)) {
        return '${ApiConstants.abiSourceId}_$postId';
      }
      return _normalizeAbiUrl(trimmedUrl);
    }

    return null;
  }

  static String _resolveSummary({
    required String summaryFromDescription,
    required String contentPlain,
    required String fallbackTitle,
  }) {
    final cleanDesc = summaryFromDescription.trim();
    if (cleanDesc.length >= 20) {
      return _truncateCleanly(cleanDesc, maxChars: 340);
    }

    final flatContent = contentPlain.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flatContent.isNotEmpty) {
      return _truncateCleanly(flatContent, maxChars: 300);
    }

    return cleanDesc.isNotEmpty ? cleanDesc : fallbackTitle;
  }

  /// Recorta un texto largo a un máximo aproximado de [maxChars] sin cortar
  /// palabras a la mitad, priorizando cierres de oración si están cerca.
  static String _truncateCleanly(String text, {int maxChars = 300}) {
    if (text.length <= maxChars) return text;

    final slice = text.substring(0, maxChars);

    final lastSentenceEnd = slice.lastIndexOf('. ');
    if (lastSentenceEnd >= (maxChars * 0.55).round()) {
      return slice.substring(0, lastSentenceEnd + 1).trim();
    }

    final lastSpace = slice.lastIndexOf(' ');
    if (lastSpace > 0) {
      var wordBoundary = slice.substring(0, lastSpace).trim();
      wordBoundary = wordBoundary.replaceAll(RegExp(r'[,:;–-]+$'), '').trim();
      return '$wordBoundary…';
    }

    return '$slice…';
  }

  /// Extrae imagen destacada explícita del nodo `<item>` del RSS:
  /// 1. Nodos explícitos `<featuredImage>` / `<post-thumbnail>` si existen.
  /// 2. `<media:content url="...">` o `<media:thumbnail url="...">`.
  /// 3. `<enclosure url="..." type="image/...">`.
  static String? _extractDirectRssImageUrl(XmlElement item) {
    // 1. Etiqueta directa de imagen destacada en el RSS si algún plugin la expone
    for (final child in item.childElements) {
      final local = child.name.local.toLowerCase();
      if (local == 'featuredimage' ||
          local == 'featured_image' ||
          local == 'post-thumbnail') {
        final attrUrl = _normalizeImageUrl(child.getAttribute('url'));
        if (attrUrl != null) return attrUrl;
        final textUrl = _normalizeImageUrl(child.innerText);
        if (textUrl != null) return textUrl;
      }
    }

    // 2. <media:content url="..."> o <media:thumbnail url="...">
    for (final child in item.childElements) {
      final isMediaElement =
          (child.name.namespaceUri == _mediaNs ||
              child.name.prefix == 'media') &&
          (child.name.local == 'content' || child.name.local == 'thumbnail');
      if (isMediaElement) {
        final mediaUrl = _normalizeImageUrl(child.getAttribute('url'));
        final medium = child.getAttribute('medium')?.toLowerCase();
        final type = child.getAttribute('type')?.toLowerCase();
        final isAllowedMedia =
            (medium == null || medium == 'image') &&
            (type == null || type.startsWith('image/'));
        if (mediaUrl != null && isAllowedMedia) {
          return mediaUrl;
        }
      }
    }

    // 3. <enclosure url="..." type="image/...">
    for (final enclosure in item.findElements('enclosure')) {
      final enclosureUrl = _normalizeImageUrl(enclosure.getAttribute('url'));
      final type = enclosure.getAttribute('type')?.toLowerCase() ?? '';
      if (enclosureUrl != null &&
          (type.startsWith('image/') || _looksLikeImagePath(enclosureUrl))) {
        return enclosureUrl;
      }
    }

    return null;
  }

  static ({String category, List<String> tags}) _extractCategoryAndTags(
    XmlElement item,
  ) {
    final rawCategories = <String>[];
    final seenNormalized = <String>{};

    for (final catElement in item.findElements('category')) {
      final decoded = HtmlSanitizer.decodeHtmlEntities(
        catElement.innerText,
      ).trim();
      if (decoded.isEmpty) continue;

      final comparisonKey = _normalizeComparisonKey(decoded);
      if (seenNormalized.add(comparisonKey)) {
        rawCategories.add(decoded);
      }
    }

    if (rawCategories.isEmpty) {
      return (
        category: ApiConstants.defaultCategoryFallback,
        tags: const <String>[],
      );
    }

    String? resolvedMainCategory;
    int matchedIndex = -1;

    for (var i = 0; i < rawCategories.length; i++) {
      final canonical = _matchKnownMainCategory(rawCategories[i]);
      if (canonical != null) {
        resolvedMainCategory = canonical;
        matchedIndex = i;
        break;
      }
    }

    if (resolvedMainCategory == null) {
      resolvedMainCategory = rawCategories.first;
      matchedIndex = 0;
    }

    final tags = <String>[];
    final mainKey = _normalizeComparisonKey(resolvedMainCategory);
    for (var i = 0; i < rawCategories.length; i++) {
      if (i == matchedIndex) continue;
      final candidate = rawCategories[i];
      if (_normalizeComparisonKey(candidate) == mainKey) continue;
      tags.add(candidate);
    }

    return (category: resolvedMainCategory, tags: tags);
  }

  static String? _matchKnownMainCategory(String rawCategory) {
    final key = _normalizeComparisonKey(rawCategory);
    for (final known in ApiConstants.knownMainCategories) {
      if (_normalizeComparisonKey(known) == key) {
        return known;
      }
    }
    return null;
  }

  static String _normalizeComparisonKey(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u');
  }

  static String? _readElementText(XmlElement parent, String name) {
    final element = parent.getElement(name);
    if (element == null) return null;
    return element.innerText;
  }

  static String? _readNamespacedElementText(
    XmlElement parent, {
    required String localName,
    required String namespaceUri,
    required String qualifiedFallback,
  }) {
    final byNamespace = parent.getElement(localName, namespace: namespaceUri);
    if (byNamespace != null) {
      return byNamespace.innerText;
    }

    final byQualified = parent.getElement(qualifiedFallback);
    if (byQualified != null) {
      return byQualified.innerText;
    }

    for (final child in parent.childElements) {
      if (child.name.qualified == qualifiedFallback ||
          (child.name.local == localName && child.name.prefix != null)) {
        return child.innerText;
      }
    }
    return null;
  }

  static String _normalizeAbiUrl(String? rawUrl) {
    if (rawUrl == null) return '';
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.toLowerCase() == 'www.abi.bo') {
      return uri.replace(host: 'abi.bo').toString();
    }
    return trimmed;
  }

  static String? _normalizeImageUrl(String? rawUrl) {
    final normalized = _normalizeAbiUrl(rawUrl);
    if (normalized.isEmpty) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return uri.toString();
  }

  static bool _looksLikeImagePath(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }
}

class _ParsedRssEntry {
  const _ParsedRssEntry({
    required this.model,
    required this.hasDirectRssFeaturedImage,
    required this.contentImageUrls,
  });

  final ArticleModel model;
  final bool hasDirectRssFeaturedImage;
  final List<String> contentImageUrls;
}
