import 'package:nexusbo/features/news/data/models/article_model.dart';

/// Contrato polimórfico para fuentes individuales de noticias en NexusBO.
///
/// Cada implementación de [NewsSource] es responsable exclusivamente de:
/// - Conectar con el medio asignado (vía RSS, REST API o extracción estructurada).
/// - Parsear su formato específico.
/// - Normalizar los datos en instancias inmutables de [ArticleModel].
///
/// Ninguna fuente debe interactuar directamente con SQLite, Riverpod,
/// notificaciones locales ni elementos visuales.
abstract interface class NewsSource {
  /// Identificador único y prefijo canónico de la fuente (e.g. `'abi'`, `'dtv'`, `'eldeber'`).
  String get id;

  /// Nombre público del medio de comunicación (e.g. `'ABI'`, `'DTV'`, `'El Deber'`).
  String get name;

  /// Prioridad u orden relativo para listados y vistas en la interfaz.
  int get sortOrder;

  /// Consulta la fuente externa y devuelve los artículos más recientes
  /// completamente normalizados y listos para ser persistidos en SQLite.
  Future<List<ArticleModel>> fetchLatestArticles();
}

