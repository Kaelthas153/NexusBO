import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';

/// Provider reactivo para la pestaña Favoritos (conectado a SQLite mediante [NewsRepository]).
final favoritesProvider = FutureProvider.autoDispose<List<Article>>((ref) async {
  final repository = ref.watch(newsRepositoryProvider);
  return repository.getFavorites();
});

