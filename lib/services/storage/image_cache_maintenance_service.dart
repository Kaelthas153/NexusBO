import 'package:flutter/painting.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';

/// Servicio encargado del mantenimiento y almacenamiento por niveles de imágenes.
///
/// Política de NexusBO:
/// - Noticias de hasta 7 días conservan imágenes en caché para una lectura visual ágil.
/// - Noticias mayores a 7 días pasan a modo reducido (se desaloja la imagen en memoria/caché,
///   se conserva la metadata textual y la URL en SQLite, y la UI las presenta en formato
///   editorial tipográfico sin re-descarga innecesaria).
class ImageCacheMaintenanceService {
  const ImageCacheMaintenanceService();

  static const Duration defaultMaxAge = Duration(days: 7);

  /// Desaloja de la caché en memoria y del gestor de imágenes de Flutter aquellas
  /// URLs correspondientes a noticias con antigüedad mayor a [maxAge].
  int evictOldImages(
    Iterable<Article> articles, {
    Duration maxAge = defaultMaxAge,
    DateTime? referenceTimeUtc,
  }) {
    final now = (referenceTimeUtc ?? DateTime.now()).toUtc();
    final cutoff = now.subtract(maxAge);
    var evictedCount = 0;

    final imageCache = PaintingBinding.instance.imageCache;

    for (final article in articles) {
      if (article.publishedAt.isBefore(cutoff)) {
        for (final url in article.imageUrls) {
          if (url.trim().isNotEmpty) {
            try {
              imageCache.evict(NetworkImage(url));
              evictedCount++;
            } catch (_) {
              // Si la imagen no estaba cargada en memoria, la excepción es inocua.
            }
          }
        }
      }
    }

    return evictedCount;
  }

  /// Verifica si un artículo específico se encuentra dentro del rango de imágenes activas (<= 7 días).
  static bool shouldRetainImage(
    DateTime publishedAtUtc, {
    Duration maxAge = defaultMaxAge,
    DateTime? referenceTimeUtc,
  }) {
    final now = (referenceTimeUtc ?? DateTime.now()).toUtc();
    final difference = now.difference(publishedAtUtc.toUtc());
    return difference <= maxAge;
  }
}
