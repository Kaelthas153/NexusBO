import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/widgets/category_tag.dart';
import 'package:nexusbo/core/widgets/editorial_image_placeholder.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';

/// Bloque de apertura para la noticia principal destacada en portada.
/// Sin contenedores tipo tarjeta ni sombras; jerarquía guiada por tipografía,
/// fotografía amplia (cuando existe en ABI) y espacio en blanco.
class FeaturedArticleItem extends StatelessWidget {
  const FeaturedArticleItem({
    super.key,
    required this.article,
    required this.onTap,
  });

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;
    final timeAgo = BoliviaDateFormatter.formatFeedTimestamp(
      article.publishedAt,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryTag(
                  label: article.category,
                  isHighlighted: true,
                ),
                const SizedBox(width: 10),
                Text(
                  'TEMA CENTRAL',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                if (article.isFavorite)
                  Icon(
                    Icons.bookmark_rounded,
                    size: 16,
                    color: colors.primary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              article.title,
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              article.summary,
              style: textTheme.bodyMedium,
            ),
            if (article.hasValidFreshImage) ...[
              const SizedBox(height: 16),
              EditorialArticleImage(
                imageUrl: article.imageUrl,
                caption: article.title,
                aspectRatio: 16 / 9.5,
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  article.sourceName,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: textTheme.bodySmall,
                  ),
                ),
                Flexible(
                  child: Text(
                    article.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: textTheme.bodySmall,
                  ),
                ),
                Text(
                  timeAgo,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
