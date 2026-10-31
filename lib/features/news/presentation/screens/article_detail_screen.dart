import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/widgets/category_tag.dart';
import 'package:nexusbo/core/widgets/editorial_divider.dart';
import 'package:nexusbo/core/widgets/editorial_image_placeholder.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';
import 'package:nexusbo/features/news/presentation/screens/article_image_viewer_screen.dart';

/// Vista de lectura editorial de un artículo real conectado a SQLite.
///
/// Al abrirse, registra automáticamente `markAsRead(id)` en SQLite, permite
/// alternar el estado de favorito (`toggleFavorite(id)`) y abrir el visor de
/// imágenes en pantalla completa al tocar cualquiera de las fotografías.
class ArticleDetailScreen extends ConsumerStatefulWidget {
  const ArticleDetailScreen({
    super.key,
    required this.article,
  });

  final Article article;

  @override
  ConsumerState<ArticleDetailScreen> createState() =>
      _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends ConsumerState<ArticleDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(newsFeedProvider.notifier).markAsRead(widget.article.id);
    });
  }

  Future<void> _handleToggleFavorite(Article currentArticle) async {
    await ref.read(newsFeedProvider.notifier).toggleFavorite(currentArticle.id);
    if (!mounted) return;
    final willBeFavorite = !currentArticle.isFavorite;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            willBeFavorite
                ? 'Artículo agregado a Favoritos.'
                : 'Artículo eliminado de Favoritos.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _handleOpenOriginalSource(Article currentArticle) {
    Clipboard.setData(ClipboardData(text: currentArticle.url));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Enlace original copiado: ${currentArticle.url}',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openImageViewer(Article currentArticle, int initialIndex) {
    if (currentArticle.imageUrls.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleImageViewerScreen(
          imageUrls: currentArticle.imageUrls,
          initialIndex: initialIndex,
          articleTitle: currentArticle.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    final detailAsync = ref.watch(articleDetailProvider(widget.article.id));
    final currentArticle = detailAsync.value ?? widget.article;

    final formattedDate = BoliviaDateFormatter.formatFullArticleDate(
      currentArticle.publishedAt,
    );

    final additionalImages = currentArticle.imageUrls.length > 1
        ? currentArticle.imageUrls.sublist(1)
        : const <String>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              currentArticle.isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: currentArticle.isFavorite
                  ? colors.primary
                  : colors.textPrimary,
            ),
            tooltip: currentArticle.isFavorite
                ? 'Quitar de Favoritos'
                : 'Agregar a Favoritos',
            onPressed: () => _handleToggleFavorite(currentArticle),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20),
            tooltip: 'Fuente original',
            onPressed: () => _handleOpenOriginalSource(currentArticle),
          ),
          const SizedBox(width: 6),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: EditorialDivider(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: CategoryTag(
              label: currentArticle.category,
              isHighlighted: true,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            currentArticle.title,
            style: textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            currentArticle.summary,
            style: textTheme.titleMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          const EditorialDivider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                currentArticle.sourceName,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('·', style: textTheme.bodySmall),
              ),
              Expanded(
                child: Text(
                  '${currentArticle.author} · $formattedDate',
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const EditorialDivider(),

          // Imagen principal interactiva (abre visor en pantalla completa)
          if (currentArticle.hasValidFreshImage) ...[
            const SizedBox(height: 20),
            _TappableArticleImage(
              imageUrl: currentArticle.imageUrl!,
              caption: currentArticle.title,
              badgeText: currentArticle.hasMultipleImages
                  ? '1 / ${currentArticle.imageUrls.length} · Ampliar'
                  : 'Ampliar',
              onTap: () => _openImageViewer(currentArticle, 0),
            ),
          ] else if (currentArticle.isOlderThan7Days && currentArticle.hasVisualMedia) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceSecondary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modo reducido: Noticia mayor a 7 días. Las imágenes permanecen archivadas para optimizar el almacenamiento local.',
                      style: textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 22),
          for (final paragraph in currentArticle.paragraphs) ...[
            Text(
              paragraph,
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
          ],

          // Imágenes adicionales contenidas dentro del artículo
          if (currentArticle.hasValidFreshImage && additionalImages.isNotEmpty) ...[
            const SizedBox(height: 8),
            const EditorialDivider(),
            const SizedBox(height: 14),
            Text(
              'IMÁGENES ADICIONALES DEL ARTÍCULO (${additionalImages.length})',
              style: textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < additionalImages.length; i++) ...[
              _TappableArticleImage(
                imageUrl: additionalImages[i],
                caption: currentArticle.title,
                badgeText:
                    '${i + 2} / ${currentArticle.imageUrls.length} · Ampliar',
                onTap: () => _openImageViewer(currentArticle, i + 1),
              ),
              const SizedBox(height: 16),
            ],
          ],

          if (currentArticle.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in currentArticle.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      tag,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          InkWell(
            onTap: () => _handleOpenOriginalSource(currentArticle),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceSecondary,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.language,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fuente oficial: Agencia Boliviana de Información (abi.bo)',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentArticle.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TappableArticleImage extends StatelessWidget {
  const _TappableArticleImage({
    required this.imageUrl,
    required this.caption,
    required this.badgeText,
    required this.onTap,
  });

  final String imageUrl;
  final String caption;
  final String badgeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          EditorialArticleImage(
            imageUrl: imageUrl,
            caption: caption,
            aspectRatio: 16 / 10,
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xCC101719),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.zoom_out_map,
                    size: 13,
                    color: AppColors.darkTextPrimary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
