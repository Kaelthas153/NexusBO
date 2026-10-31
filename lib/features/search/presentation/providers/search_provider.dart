import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';

/// Notifier para el término de búsqueda actual en la pestaña Buscar.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

/// Resultados de búsqueda local en SQLite según el término en [searchQueryProvider].
/// Exclusivamente consulta SQLite, sin invocar nunca al feed RSS.
final searchResultsProvider = FutureProvider.autoDispose<List<Article>>((
  ref,
) async {
  final rawQuery = ref.watch(searchQueryProvider);
  final trimmed = rawQuery.trim();
  if (trimmed.isEmpty) {
    return const <Article>[];
  }

  final repository = ref.watch(newsRepositoryProvider);
  return repository.searchArticles(trimmed);
});

