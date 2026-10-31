import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/core/widgets/editorial_divider.dart';
import 'package:nexusbo/core/widgets/empty_state_view.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/presentation/screens/article_detail_screen.dart';
import 'package:nexusbo/features/news/presentation/widgets/editorial_article_row.dart';
import 'package:nexusbo/features/search/presentation/providers/search_provider.dart';

/// Pantalla de Búsqueda local conectada exclusivamente a SQLite mediante
/// [searchResultsProvider] con debounce de 250ms.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).setQuery(value);
    });
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() {});
    ref.read(searchQueryProvider.notifier).clear();
  }

  void _openArticleDetail(BuildContext context, Article article) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleDetailScreen(article: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;
    final activeQuery = ref.watch(searchQueryProvider).trim();
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HEMEROTECA LOCAL',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Buscar',
                    style: textTheme.displaySmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    onChanged: _onQueryChanged,
                    textInputAction: TextInputAction.search,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar por titular, tema o institución...',
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Limpiar búsqueda',
                              icon: Icon(
                                Icons.close,
                                size: 18,
                                color: colors.textSecondary,
                              ),
                              onPressed: _clearSearch,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const EditorialDivider(),
            Expanded(
              child: activeQuery.isEmpty
                  ? const SingleChildScrollView(
                      child: EmptyStateView(
                        icon: Icons.manage_search_outlined,
                        eyebrow: 'Búsqueda en archivo',
                        title: 'Explora las noticias almacenadas',
                        description:
                            'Ingresa una palabra clave, institución o categoría para buscar instantáneamente dentro de los artículos descargados en tu dispositivo.',
                      ),
                    )
                  : resultsAsync.when(
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
                          icon: Icons.error_outline,
                          eyebrow: 'Búsqueda local',
                          title: 'No se pudo completar la consulta',
                          description:
                              'Intenta buscar nuevamente con otro término.',
                        ),
                      ),
                      data: (results) {
                        if (results.isEmpty) {
                          return SingleChildScrollView(
                            child: EmptyStateView(
                              icon: Icons.search_off_outlined,
                              eyebrow: 'Sin coincidencias',
                              title: 'No se encontraron noticias para "$activeQuery"',
                              description:
                                  'Prueba con otra palabra clave o verifica los titulares descargados en la portada.',
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.only(bottom: 28),
                          itemCount: results.length,
                          separatorBuilder: (_, _) => const EditorialDivider(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                          ),
                          itemBuilder: (context, index) {
                            final article = results[index];
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
