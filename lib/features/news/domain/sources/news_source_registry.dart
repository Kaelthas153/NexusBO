import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Registro central de fuentes de noticias disponibles en NexusBO.
///
/// Gestiona la colección de implementaciones [NewsSource] registradas,
/// permitiendo su consulta por ID, listado ordenado y soporte para futura
/// habilitación o deshabilitación dinámica sin alterar el repositorio.
class NewsSourceRegistry {
  NewsSourceRegistry({List<NewsSource>? initialSources}) {
    if (initialSources != null) {
      for (final source in initialSources) {
        register(source);
      }
    }
  }

  final Map<String, NewsSource> _sources = <String, NewsSource>{};

  /// Registra una nueva fuente en el catálogo.
  void register(NewsSource source) {
    _sources[source.id] = source;
  }

  /// Desregistra una fuente del catálogo por su ID.
  void unregister(String sourceId) {
    _sources.remove(sourceId);
  }

  /// Retorna todas las fuentes registradas ordenadas por [NewsSource.sortOrder].
  List<NewsSource> getAllSources() {
    final list = _sources.values.toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List<NewsSource>.unmodifiable(list);
  }

  /// Retorna una fuente específica por su identificador único (e.g. `'abi'`, `'dtv'`, `'eldeber'`).
  NewsSource? getSourceById(String id) => _sources[id];

  /// Cantidad total de fuentes registradas.
  int get count => _sources.length;

  /// Retorna las fuentes habilitadas (en esta fase inicial, todas las registradas).
  List<NewsSource> getEnabledSources() => getAllSources();
}

