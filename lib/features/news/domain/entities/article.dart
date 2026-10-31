/// Entidad de dominio inmutable que representa una noticia en NexusBO.
///
/// Reglas de dominio:
/// - Sin dependencias de Flutter ni de paquetes de infraestructura.
/// - [publishedAt], [fetchedAt] y [favoritedAt] representan instantes en UTC.
/// - [imageUrl] representa la imagen principal utilizada en portada y listados.
/// - [imageUrls] almacena todas las imágenes válidas del artículo (incluida la
///   principal en primera posición) para la vista de detalle y el visor.
class Article {
  Article({
    required this.id,
    required this.title,
    required this.summary,
    required this.contentPlain,
    required this.url,
    String? imageUrl,
    List<String>? imageUrls,
    required this.author,
    required this.sourceId,
    required this.sourceName,
    required this.category,
    required List<String> tags,
    required DateTime publishedAt,
    required DateTime fetchedAt,
    this.isFavorite = false,
    DateTime? favoritedAt,
    this.isRead = false,
  }) : imageUrl = _resolveMainImage(imageUrl, imageUrls),
       imageUrls = List<String>.unmodifiable(
         _resolveAllImages(imageUrl, imageUrls),
       ),
       tags = List<String>.unmodifiable(tags),
       publishedAt = publishedAt.toUtc(),
       fetchedAt = fetchedAt.toUtc(),
       favoritedAt = favoritedAt?.toUtc();

  final String id;
  final String title;
  final String summary;
  final String contentPlain;
  final String url;

  /// Imagen principal utilizada en Home y listados (`null` si el artículo es
  /// puramente tipográfico).
  final String? imageUrl;

  /// Lista ordenada de todas las imágenes válidas del artículo.
  final List<String> imageUrls;

  final String author;
  final String sourceId;
  final String sourceName;
  final String category;
  final List<String> tags;
  final DateTime publishedAt;
  final DateTime fetchedAt;
  final bool isFavorite;
  final DateTime? favoritedAt;
  final bool isRead;

  /// Indica si el artículo dispone de al menos una imagen válida para mostrar.
  bool get hasVisualMedia => imageUrl != null && imageUrl!.trim().isNotEmpty;

  /// Indica si el artículo supera los 7 días de antigüedad (modo reducido de almacenamiento).
  bool get isOlderThan7Days =>
      DateTime.now().toUtc().difference(publishedAt).inDays > 7;

  /// Indica si la imagen debe mostrarse en la UI activa o si pasa a modo editorial tipográfico.
  bool get hasValidFreshImage => hasVisualMedia && !isOlderThan7Days;

  /// Indica si el artículo cuenta con más de una imagen disponible.
  bool get hasMultipleImages => imageUrls.length > 1;

  /// Divide [contentPlain] en párrafos lógicos para la vista de lectura.
  List<String> get paragraphs {
    if (contentPlain.trim().isEmpty) return const <String>[];
    return contentPlain
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
  }

  Article copyWith({
    String? id,
    String? title,
    String? summary,
    String? contentPlain,
    String? url,
    String? imageUrl,
    List<String>? imageUrls,
    bool clearImageUrl = false,
    String? author,
    String? sourceId,
    String? sourceName,
    String? category,
    List<String>? tags,
    DateTime? publishedAt,
    DateTime? fetchedAt,
    bool? isFavorite,
    DateTime? favoritedAt,
    bool clearFavoritedAt = false,
    bool? isRead,
  }) {
    return Article(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      contentPlain: contentPlain ?? this.contentPlain,
      url: url ?? this.url,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      imageUrls: clearImageUrl
          ? const <String>[]
          : (imageUrls ?? this.imageUrls),
      author: author ?? this.author,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      publishedAt: publishedAt ?? this.publishedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      favoritedAt: clearFavoritedAt ? null : (favoritedAt ?? this.favoritedAt),
      isRead: isRead ?? this.isRead,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Article) return false;
    return id == other.id &&
        title == other.title &&
        summary == other.summary &&
        contentPlain == other.contentPlain &&
        url == other.url &&
        imageUrl == other.imageUrl &&
        _listEquals(imageUrls, other.imageUrls) &&
        author == other.author &&
        sourceId == other.sourceId &&
        sourceName == other.sourceName &&
        category == other.category &&
        _listEquals(tags, other.tags) &&
        publishedAt.millisecondsSinceEpoch ==
            other.publishedAt.millisecondsSinceEpoch &&
        fetchedAt.millisecondsSinceEpoch ==
            other.fetchedAt.millisecondsSinceEpoch &&
        isFavorite == other.isFavorite &&
        favoritedAt?.millisecondsSinceEpoch ==
            other.favoritedAt?.millisecondsSinceEpoch &&
        isRead == other.isRead;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    summary,
    contentPlain,
    url,
    imageUrl,
    Object.hashAll(imageUrls),
    author,
    sourceId,
    sourceName,
    category,
    Object.hashAll(tags),
    publishedAt.millisecondsSinceEpoch,
    fetchedAt.millisecondsSinceEpoch,
    isFavorite,
    favoritedAt?.millisecondsSinceEpoch,
    isRead,
  );

  @override
  String toString() {
    return 'Article(id: $id, title: $title, category: $category, '
        'imageUrl: $imageUrl, imageCount: ${imageUrls.length}, '
        'publishedAt: ${publishedAt.toIso8601String()}, '
        'isFavorite: $isFavorite, isRead: $isRead)';
  }

  static String? _resolveMainImage(String? primary, List<String>? all) {
    final cleanPrimary = primary?.trim();
    if (cleanPrimary != null && cleanPrimary.isNotEmpty) {
      return cleanPrimary;
    }
    if (all != null) {
      for (final item in all) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
    return null;
  }

  static List<String> _resolveAllImages(String? primary, List<String>? all) {
    final result = <String>[];
    final cleanPrimary = primary?.trim();
    if (cleanPrimary != null && cleanPrimary.isNotEmpty) {
      result.add(cleanPrimary);
    }
    if (all != null) {
      for (final item in all) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty && !result.contains(trimmed)) {
          result.add(trimmed);
        }
      }
    }
    return result;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
