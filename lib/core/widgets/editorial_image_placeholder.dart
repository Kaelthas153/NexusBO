import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';

/// Imagen editorial con soporte para URL remota real (`Image.network`) y
/// fallback sobrio a placeholder periodístico durante la carga o sin conexión.
class EditorialArticleImage extends StatelessWidget {
  const EditorialArticleImage({
    super.key,
    required this.imageUrl,
    required this.caption,
    this.aspectRatio = 16 / 10,
    this.compact = false,
  });

  final String? imageUrl;
  final String caption;
  final double aspectRatio;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final cleanUrl = imageUrl?.trim();

    if (cleanUrl == null || cleanUrl.isEmpty) {
      return EditorialImagePlaceholder(
        caption: caption,
        aspectRatio: aspectRatio,
        compact: compact,
      );
    }

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: colors.border,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          cleanUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return EditorialImagePlaceholder(
              caption: caption,
              aspectRatio: aspectRatio,
              compact: compact,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return EditorialImagePlaceholder(
              caption: caption,
              aspectRatio: aspectRatio,
              compact: compact,
            );
          },
        ),
      ),
    );
  }
}

/// Placeholder editorial sobrio para representar fotografías periodísticas
/// cuando una imagen remota está cargando o no está disponible sin conexión.
class EditorialImagePlaceholder extends StatelessWidget {
  const EditorialImagePlaceholder({
    super.key,
    required this.caption,
    this.aspectRatio = 16 / 10,
    this.compact = false,
  });

  final String caption;
  final double aspectRatio;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: colors.border,
            width: 1,
          ),
        ),
        padding: EdgeInsets.all(compact ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  size: compact ? 16 : 20,
                  color: colors.textSecondary,
                ),
                if (!compact)
                  Text(
                    'ARCHIVO / ABI',
                    style: textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.8,
                    ),
                  ),
              ],
            ),
            if (!compact)
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
