import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/core/widgets/editorial_divider.dart';
import 'package:nexusbo/core/widgets/empty_state_view.dart';
import 'package:nexusbo/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/presentation/screens/article_detail_screen.dart';
import 'package:nexusbo/features/news/presentation/widgets/editorial_article_row.dart';

/// Pantalla de Favoritos conectada a SQLite mediante [favoritesProvider].
/// Funciona completamente sin conexión y preserva el diseño editorial.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  void _openArticleDetail(BuildContext context, Article article) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleDetailScreen(article: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;
    final favoritesAsync = ref.watch(favoritesProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LECTURA SIN CONEXIÓN',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Favoritos',
                    style: textTheme.displaySmall,
                  ),
                ],
              ),
            ),
            const EditorialDivider(),
            Expanded(
              child: favoritesAsync.when(
                loading: () => Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                ),
                error: (_, _) => const SingleChildScrollView(
                  child: EmptyStateView(
                    icon: Icons.bookmark_border_rounded,
                    eyebrow: 'Colección personal',
                    title: 'No se pudieron cargar tus favoritos',
                    description:
                        'Intenta abrir nuevamente esta sección en unos instantes.',
                  ),
                ),
                data: (favorites) {
                  if (favorites.isEmpty) {
                    return const SingleChildScrollView(
                      child: EmptyStateView(
                        icon: Icons.bookmark_border_rounded,
                        eyebrow: 'Colección personal',
                        title: 'Todavía no tienes noticias en favoritos',
                        description:
                            'Marca cualquier artículo con el ícono de marcador para conservarlo en tu archivo personal y leerlo en cualquier momento, incluso sin conexión.',
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 28),
                    itemCount: favorites.length,
                    separatorBuilder: (_, _) => const EditorialDivider(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                    ),
                    itemBuilder: (context, index) {
                      final article = favorites[index];
                      return EditorialArticleRow(
                        article: article,
                        onTap: () => _openArticleDetail(context, article),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
