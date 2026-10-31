import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/widgets/category_tag.dart';
import 'package:nexusbo/core/widgets/editorial_image_placeholder.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';

/// Fila editorial para noticias secundarias.
/// Se adapta fluidamente tanto a artículos puramente tipográficos como a
/// aquellos acompañados de fotografía real de ABI.
class EditorialArticleRow extends StatelessWidget {
  const EditorialArticleRow({
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryTag(label: article.category),
                const Spacer(),
                if (article.isFavorite)
                  Icon(
                    Icons.bookmark_rounded,
                    size: 15,
                    color: colors.primary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        article.summary,
                        maxLines: article.hasValidFreshImage ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (article.hasValidFreshImage) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: EditorialArticleImage(
                      imageUrl: article.imageUrl,
                      caption: article.title,
                      aspectRatio: 1,
                      compact: true,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
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
                Text(
                  timeAgo,
                  style: textTheme.bodySmall,
                ),
                if (article.isRead) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '·',
                      style: textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    'Leído',
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
