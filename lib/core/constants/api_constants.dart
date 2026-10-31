/// Constantes de red, fuente inicial y clasificación editorial de NexusBO.
abstract final class ApiConstants {
  /// URL oficial del feed RSS 2.0 de la Agencia Boliviana de Información.
  /// IMPORTANTE: Se utiliza estrictamente `abi.bo` sin `www` porque
  /// `https://www.abi.bo` falla en la negociación TLS del servidor.
  static const String abiFeedUrl = 'https://abi.bo/feed/';

  static const String abiSourceId = 'abi';
  static const String abiSourceName = 'ABI';
  static const String defaultAuthorFallback = 'ABI';
  static const String defaultCategoryFallback = 'General';

  /// User-Agent identificable para las peticiones HTTP del lector RSS.
  static const String userAgent = 'NexusBO/0.1 Android RSS Reader';

  /// User-Agent estándar compatible con sitios protegidos por inspección de cabeceras públicas.
  static const String browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

  // --- La Razón ---
  static const String laRazonFeedUrl = 'https://larazon.bo/feed/';
  static const String laRazonSourceId = 'larazon';
  static const String laRazonSourceName = 'La Razón';

  // --- El Diario ---
  static const String elDiarioFeedUrl = 'https://www.eldiario.net/portal/feed/';
  static const String elDiarioSourceId = 'eldiario';
  static const String elDiarioSourceName = 'El Diario';

  // --- El País (Tarija) ---
  static const String elPaisSitemapUrl = 'https://elpais.bo/sitemap-google-news.xml';
  static const String elPaisSourceId = 'elpais';
  static const String elPaisSourceName = 'El País';

  // --- Correo del Sur (Sucre) ---
  static const String correoDelSurHomeUrl = 'https://correodelsur.com/';
  static const String correoDelSurSourceId = 'correodelsur';
  static const String correoDelSurSourceName = 'Correo del Sur';

  // --- Unitel (Red Nacional) ---
  static const String unitelNewsUrl = 'https://unitel.bo/noticias';
  static const String unitelSourceId = 'unitel';
  static const String unitelSourceName = 'Unitel';

  // --- Agencia de Noticias Fides (ANF) ---
  static const String anfHomeUrl = 'https://www.noticiasfides.com/';
  static const String anfSourceId = 'anf';
  static const String anfSourceName = 'ANF';

  /// Cabecera Accept apropiada para feeds RSS/XML.
  static const String acceptHeader =
      'application/rss+xml, application/xml, text/xml, */*;q=0.8';

  /// Timeouts HTTP razonables para conexiones móviles.
  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 10);

  /// Categorías principales conocidas de ABI utilizadas en la barra editorial.
  static const List<String> knownMainCategories = <String>[
    'Política',
    'Economía',
    'Sociedad',
    'Seguridad',
    'Culturas',
    'Deportes',
  ];
}

