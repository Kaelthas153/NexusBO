import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Utilidades para limpiar fragmentos HTML provenientes de feeds RSS/WordPress
/// y extraer metadatos de imágenes utilizando el parser DOM de `package:html`.
abstract final class HtmlSanitizer {
  static const Set<String> _removedElements = <String>{
    'script',
    'style',
    'noscript',
    'iframe',
    'svg',
    'canvas',
    'form',
  };

  static const Set<String> _blockElements = <String>{
    'p',
    'div',
    'section',
    'article',
    'blockquote',
    'pre',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'ul',
    'ol',
    'figure',
    'figcaption',
    'tr',
  };

  /// Patrón para identificar el pie automático que Yoast SEO / WordPress
  /// inyecta al final de los feeds RSS (e.g. ABI, El Diario, La Razón):
  /// - "La entrada [Título] se publicó primero en [Medio]."
  /// - "The post [Título] appeared first on [Medio]."
  static final RegExp _wordPressFooterPattern = RegExp(
    r'^(?:La entrada\s+.+?\s+se public[oó] primero en\s+.+?|The post\s+.+?\s+appeared first on\s+.+?)\.?$',
    caseSensitive: false,
  );

  static final RegExp _inlineFooterSuffixPattern = RegExp(
    r'\s*(?:La entrada\s+.+?\s+se public[oó] primero en\s+.+?|The post\s+.+?\s+appeared first on\s+.+?)\.?\s*$',
    caseSensitive: false,
  );

  static final RegExp _abiWordPressFooterPattern = _wordPressFooterPattern;
  static final RegExp _inlineAbiFooterSuffixPattern = _inlineFooterSuffixPattern;

  /// Sufijo de dimensiones que WordPress agrega a miniaturas/recortes
  /// (por ejemplo `foto-915x1024.jpg` respecto a `foto.jpg`).
  static final RegExp _wpDimensionSuffixPattern = RegExp(
    r'-\d+x\d+(?=\.[a-zA-Z0-9]+$)',
  );

  /// Decodifica entidades HTML (ej. `&#8230;`, `&nbsp;`, `&quot;`, `&oacute;`)
  /// y normaliza espacios en blanco en una sola línea.
  static String decodeHtmlEntities(String input) {
    if (input.isEmpty) return '';
    final fragment = html_parser.parseFragment(input);
    final text = fragment.text ?? '';
    return _normalizeInlineWhitespace(text);
  }

  /// Convierte un fragmento o documento HTML en texto plano limpio:
  /// - Elimina nodos `script`, `style`, etc.
  /// - Decodifica entidades HTML.
  /// - Preserva la separación lógica entre párrafos mediante `\n\n`.
  /// - Elimina espacios repetidos innecesarios.
  /// - Remueve el pie automático de WordPress/ABI ("La entrada ... se publicó primero en ABI.").
  static String sanitizeToPlainText(
    String rawHtml, {
    bool preserveParagraphs = true,
  }) {
    if (rawHtml.trim().isEmpty) return '';

    final documentFragment = html_parser.parseFragment(rawHtml);
    _removeUnwantedNodes(documentFragment);

    final buffer = StringBuffer();
    _extractTextFromNode(documentFragment, buffer);

    final rawExtracted = buffer.toString();
    final rawParagraphs = rawExtracted.split(RegExp(r'\n\s*\n|\r\n\s*\r\n'));

    final cleanedParagraphs = <String>[];
    for (final rawParagraph in rawParagraphs) {
      var paragraph = _normalizeInlineWhitespace(rawParagraph);
      if (paragraph.isEmpty) continue;

      // Omitir si el párrafo completo es el pie automático de WordPress/ABI
      if (_abiWordPressFooterPattern.hasMatch(paragraph)) {
        continue;
      }

      // Si el pie de WordPress/ABI quedó pegado al final del último párrafo
      paragraph = paragraph
          .replaceFirst(_inlineAbiFooterSuffixPattern, '')
          .trim();

      // Limpiar sufijos de truncamiento de extractos WordPress como "[…]" o "[...]"
      paragraph = paragraph
          .replaceAll(RegExp(r'\s*\[\s*(?:…|\.{3})\s*\]\s*$'), '…')
          .trim();

      if (paragraph.isNotEmpty &&
          !_abiWordPressFooterPattern.hasMatch(paragraph)) {
        cleanedParagraphs.add(paragraph);
      }
    }

    if (cleanedParagraphs.isEmpty) return '';
    return preserveParagraphs
        ? cleanedParagraphs.join('\n\n')
        : cleanedParagraphs.join(' ');
  }

  /// Extrae la URL de la primera imagen válida (`http` o `https`) presente
  /// dentro del fragmento HTML, o devuelve `null` si no existe ninguna.
  static String? extractFirstImageUrl(String? rawHtml) {
    final all = extractAllImageUrls(rawHtml);
    return all.isNotEmpty ? all.first : null;
  }

  /// Extrae todas las URLs de imágenes válidas (`http` o `https`) presentes
  /// en un fragmento HTML (por ejemplo `content:encoded`), preservando el
  /// orden de aparición y eliminando duplicados.
  static List<String> extractAllImageUrls(String? rawHtml) {
    if (rawHtml == null || rawHtml.trim().isEmpty) return const <String>[];

    final fragment = html_parser.parseFragment(rawHtml);
    final images = fragment.querySelectorAll('img');

    final results = <String>[];
    final seenCanonicalKeys = <String>{};

    for (final img in images) {
      final candidate = _extractUrlFromImgElement(img);
      if (candidate != null && !_isSiteIconOrAvatar(candidate)) {
        final key = canonicalImageKey(candidate);
        if (seenCanonicalKeys.add(key)) {
          results.add(candidate);
        }
      }
    }

    return results;
  }

  /// Extrae la imagen destacada/principal (`featured image`) desde el HTML de
  /// la página original de un artículo de ABI, buscando en orden:
  /// 1. `meta[property="og:image"]`
  /// 2. `meta[name="twitter:image"]` o `meta[property="twitter:image"]`
  /// 3. `img.wp-post-image` o `img.single-featured-image`
  static String? extractFeaturedImageFromArticleHtml(String? rawPageHtml) {
    if (rawPageHtml == null || rawPageHtml.trim().isEmpty) return null;

    final document = html_parser.parse(rawPageHtml);

    // 1. OpenGraph og:image
    final ogTags = document.querySelectorAll('meta[property="og:image"]');
    for (final meta in ogTags) {
      final content = _validateAndNormalizeImageUrl(meta.attributes['content']);
      if (content != null && !_isSiteIconOrAvatar(content)) {
        return content;
      }
    }

    // 2. Twitter Card image
    final twitterTags = document.querySelectorAll(
      'meta[name="twitter:image"], meta[property="twitter:image"]',
    );
    for (final meta in twitterTags) {
      final content = _validateAndNormalizeImageUrl(meta.attributes['content']);
      if (content != null && !_isSiteIconOrAvatar(content)) {
        return content;
      }
    }

    // 3. Imagen destacada de plantilla WordPress (wp-post-image)
    final wpFeaturedImg = document.querySelector(
      'img.wp-post-image, img.single-featured-image',
    );
    if (wpFeaturedImg != null) {
      final url = _extractUrlFromImgElement(wpFeaturedImg);
      if (url != null && !_isSiteIconOrAvatar(url)) {
        return url;
      }
    }

    return null;
  }

  /// Genera una clave canónica de comparación para evitar duplicar la misma
  /// fotografía cuando WordPress ofrece tanto el archivo original como un
  /// recorte con sufijo `-WxH` (ej. `foto.jpg` vs `foto-915x1024.jpg`).
  static String canonicalImageKey(String url) {
    final normalized = _validateAndNormalizeImageUrl(url) ?? url.trim();
    return normalized.toLowerCase().replaceAll(_wpDimensionSuffixPattern, '');
  }

  static String? _extractUrlFromImgElement(Element img) {
    final directSrc =
        img.attributes['src'] ??
        img.attributes['data-src'] ??
        img.attributes['data-lazy-src'];

    final validatedDirect = _validateAndNormalizeImageUrl(directSrc);
    if (validatedDirect != null) {
      return validatedDirect;
    }

    final srcset = img.attributes['srcset'];
    if (srcset != null && srcset.trim().isNotEmpty) {
      final firstCandidate = srcset.split(',').first.trim().split(' ').first;
      final validatedSrcset = _validateAndNormalizeImageUrl(firstCandidate);
      if (validatedSrcset != null) {
        return validatedSrcset;
      }
    }
    return null;
  }

  static bool _isSiteIconOrAvatar(String url) {
    final lower = url.toLowerCase();
    return lower.contains('cropped-') && lower.contains('32x32') ||
        lower.contains('/favicon') ||
        lower.contains('gravatar.com');
  }

  static void _removeUnwantedNodes(Node root) {
    final toRemove = <Node>[];
    for (final child in root.nodes) {
      if (child is Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        if (_removedElements.contains(tag)) {
          toRemove.add(child);
          continue;
        }
      }
      _removeUnwantedNodes(child);
    }
    for (final node in toRemove) {
      node.remove();
    }
  }

  static void _extractTextFromNode(Node node, StringBuffer buffer) {
    if (node is Text) {
      buffer.write(node.data);
      return;
    }

    if (node is Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'br') {
        buffer.write('\n\n');
        return;
      }

      final isBlock = _blockElements.contains(tag);
      if (isBlock) {
        buffer.write('\n\n');
      }

      for (final child in node.nodes) {
        _extractTextFromNode(child, buffer);
      }

      if (isBlock) {
        buffer.write('\n\n');
      }
      return;
    }

    for (final child in node.nodes) {
      _extractTextFromNode(child, buffer);
    }
  }

  static String _normalizeInlineWhitespace(String input) {
    return input
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), ' ')
        .trim();
  }

  static String? _validateAndNormalizeImageUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    // Normalizar subdominio www.abi.bo a abi.bo para evitar el error TLS del servidor de ABI
    if (uri.host.toLowerCase() == 'www.abi.bo') {
      return uri.replace(host: 'abi.bo').toString();
    }

    return uri.toString();
  }
}
