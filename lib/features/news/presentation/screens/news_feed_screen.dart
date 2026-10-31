import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/app/theme/theme_mode_provider.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/core/widgets/editorial_divider.dart';
import 'package:nexusbo/core/widgets/empty_state_view.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';
import 'package:nexusbo/features/news/presentation/screens/article_detail_screen.dart';
import 'package:nexusbo/features/news/presentation/widgets/category_filter_bar.dart';
import 'package:nexusbo/features/news/presentation/widgets/editorial_article_row.dart';
import 'package:nexusbo/features/news/presentation/widgets/featured_article_item.dart';
import 'package:nexusbo/features/news/presentation/widgets/source_filter_bar.dart';
import 'package:nexusbo/features/search/presentation/screens/search_screen.dart';

/// Pantalla de Inicio (Portada Editorial de NexusBO) conectada al flujo
/// Offline-First (ABI RSS -> SQLite -> Riverpod -> UI).
class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    if (currentScroll >= (maxScroll - 250)) {
      ref.read(newsFeedProvider.notifier).loadNextPage();
    }
  }

  void _openArticleDetail(BuildContext context, Article article) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleDetailScreen(article: article),
      ),
    );
  }

  Future<void> _handleManualRefresh() async {
    final result = await ref.read(newsFeedProvider.notifier).refresh();
    if (!mounted || result == null) return;
    final totalStored = ref.read(newsFeedProvider).totalCachedCount;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Sincronización completada: ${result.fetched} recibidas · '
            '${result.inserted} nuevas · $totalStored almacenadas en SQLite.',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;
    final brightness = Theme.of(context).brightness;

    final selectedCategory = ref.watch(selectedCategoryProvider);
    final selectedSourceId = ref.watch(selectedSourceIdProvider);
    final sourceOptions = ref.watch(sourceFilterOptionsProvider);
    final feedState = ref.watch(newsFeedProvider);
    final articles = feedState.articles;

    final editorialDate = BoliviaDateFormatter.formatEditorialHeader(
      DateTime.now().toUtc(),
    );

    final Article? featuredArticle =
        articles.isNotEmpty ? articles.first : null;
    final List<Article> secondaryArticles =
        articles.length > 1 ? articles.sublist(1) : const <Article>[];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: colors.primary,
          backgroundColor: colors.surface,
          onRefresh: _handleManualRefresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Cabecera editorial NexusBO
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              editorialDate,
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                                letterSpacing: 0.9,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  'Nexus',
                                  style: textTheme.displaySmall,
                                ),
                                Text(
                                  'BO',
                                  style: textTheme.displaySmall?.copyWith(
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Edición Bolivia · Despacho informativo',
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Buscar noticias',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SearchScreen(),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.search,
                          size: 22,
                          color: colors.textPrimary,
                        ),
                      ),
                      IconButton(
                        tooltip: brightness == Brightness.dark
                            ? 'Cambiar a modo claro'
                            : 'Cambiar a modo oscuro',
                        onPressed: () {
                          ref
                              .read(themeModeProvider.notifier)
                              .toggleLightDark(brightness);
                        },
                        icon: Icon(
                          brightness == Brightness.dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 21,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Selector horizontal de categorías (filtra sobre SQLite)
              SliverToBoxAdapter(
                child: CategoryFilterBar(
                  categories: kEditorialCategories,
                  selectedCategory: selectedCategory,
                  onCategorySelected: (category) {
                    ref
                        .read(newsFeedProvider.notifier)
                        .selectCategory(category);
                  },
                ),
              ),

              // Selector horizontal de fuentes (filtra sobre SQLite de manera independiente)
              SliverToBoxAdapter(
                child: SourceFilterBar(
                  options: sourceOptions,
                  selectedSourceId: selectedSourceId,
                  onSourceSelected: (sourceId) {
                    ref
                        .read(newsFeedProvider.notifier)
                        .selectSource(sourceId);
                  },
                ),
              ),

              // Indicador sutil de sincronización en segundo plano cuando ya hay caché
              if (feedState.isSyncing && !feedState.isInitialLoading)
                SliverToBoxAdapter(
                  child: LinearProgressIndicator(
                    minHeight: 1.8,
                    color: colors.primary,
                    backgroundColor: colors.surfaceSecondary,
                  ),
                ),

              // Aviso discreto cuando falló la red pero se muestra la edición local (Casos C y E)
              if (feedState.syncNoticeMessage != null)
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary,
                      border: Border(
                        bottom: BorderSide(color: colors.border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feedState.syncNoticeMessage!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            ref
                                .read(newsFeedProvider.notifier)
                                .dismissSyncNotice();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 1. Estado de carga cuando SQLite está vacío y descargando de ABI
              if (feedState.isInitialLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Descargando RSS en vivo de https://abi.bo/feed/...',
                            style: textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              // 2. CASO D: Primera instalación sin Internet y SQLite vacío -> Estado amigable + Reintentar
              else if (feedState.initialErrorMessage != null &&
                  !feedState.hasAnyCachedArticles)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 40,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.surfaceSecondary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.border),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.wifi_off_outlined,
                            size: 22,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'SIN CONEXIÓN INICIAL',
                          style: textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No se pudieron descargar los titulares de ABI',
                          style: textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          feedState.initialErrorMessage!,
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 22),
                        OutlinedButton.icon(
                          onPressed: _handleManualRefresh,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.primary,
                            side: BorderSide(color: colors.primary, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              // 3. Pantalla vaciada o categoría sin artículos en SQLite
              else if (featuredArticle == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 40,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        EmptyStateView(
                          icon: feedState.hasAnyCachedArticles
                              ? Icons.filter_list_off_outlined
                              : Icons.cloud_download_outlined,
                          eyebrow: feedState.hasAnyCachedArticles
                              ? 'Filtro sin notas'
                              : 'Caché SQLite vacía (0 artículos)',
                          title: feedState.hasAnyCachedArticles
                              ? 'No hay noticias disponibles para estos filtros'
                              : 'Pantalla limpia lista para actualizar',
                          description: feedState.hasAnyCachedArticles
                              ? 'Prueba seleccionando otra sección editorial o cambiando la fuente de noticias.'
                              : 'Desliza hacia abajo (pull-to-refresh) o pulsa el botón para descargar las noticias desde los medios bolivianos.',
                        ),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (feedState.hasAnyCachedArticles) {
                                ref
                                    .read(newsFeedProvider.notifier)
                                    .selectCategory('Todas');
                                ref
                                    .read(newsFeedProvider.notifier)
                                    .selectSource(null);
                              } else {
                                _handleManualRefresh();
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.primary,
                              side: BorderSide(
                                color: colors.primary,
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            icon: Icon(
                              feedState.hasAnyCachedArticles
                                  ? Icons.clear_all
                                  : Icons.refresh,
                              size: 18,
                            ),
                            label: Text(
                              feedState.hasAnyCachedArticles
                                  ? 'Restablecer filtros'
                                  : 'Sincronizar noticias ahora',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              // 4. Portada editorial con datos reales desde SQLite
              else ...[
                SliverToBoxAdapter(
                  child: FeaturedArticleItem(
                    article: featuredArticle,
                    onTap: () => _openArticleDetail(context, featuredArticle),
                  ),
                ),

                if (secondaryArticles.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const EditorialDivider(emphasized: true),
                          const SizedBox(height: 10),
                          Text(
                            'ÚLTIMOS DESPACHOS',
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                  SliverList.separated(
                    itemCount: secondaryArticles.length,
                    separatorBuilder: (_, _) => const EditorialDivider(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                    ),
                    itemBuilder: (context, index) {
                      final article = secondaryArticles[index];
                      return EditorialArticleRow(
                        article: article,
                        onTap: () => _openArticleDetail(context, article),
                      );
                    },
                  ),
                ],

                if (feedState.isLoadingMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 28),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
