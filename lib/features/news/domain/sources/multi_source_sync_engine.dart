import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';

/// Resultado individual de la sincronización de una fuente específica.
@immutable
class SourceSyncResult {
  const SourceSyncResult({
    required this.sourceId,
    required this.sourceName,
    required this.fetched,
    this.inserted = 0,
    this.articles = const <ArticleModel>[],
    this.error,
    required this.syncedAt,
  });

  final String sourceId;
  final String sourceName;
  final int fetched;
  final int inserted;
  final List<ArticleModel> articles;
  final Object? error;
  final DateTime syncedAt;

  bool get isSuccess => error == null;
  bool get hasError => error != null;

  SourceSyncResult copyWith({int? inserted}) {
    return SourceSyncResult(
      sourceId: sourceId,
      sourceName: sourceName,
      fetched: fetched,
      inserted: inserted ?? this.inserted,
      articles: articles,
      error: error,
      syncedAt: syncedAt,
    );
  }

  @override
  String toString() =>
      'SourceSyncResult(sourceId: $sourceId, fetched: $fetched, inserted: $inserted, error: $error)';
}

/// Resultado agregado de la sincronización de todas las fuentes.
@immutable
class MultiSourceSyncResult {
  const MultiSourceSyncResult({
    required this.results,
    required this.totalFetched,
    required this.totalInserted,
    required this.allArticles,
    required this.newArticles,
    required this.syncedAt,
    this.warning,
  });

  final List<SourceSyncResult> results;
  final int totalFetched;
  final int totalInserted;
  final List<ArticleModel> allArticles;
  final List<ArticleModel> newArticles;
  final DateTime syncedAt;
  final String? warning;

  /// Retorna `true` si al menos una fuente se sincronizó exitosamente.
  bool get hasAnySuccess => results.any((r) => r.isSuccess);

  /// Retorna `true` si todas las fuentes fallaron.
  bool get allFailed => results.isNotEmpty && results.every((r) => r.hasError);

  @override
  String toString() =>
      'MultiSourceSyncResult(totalFetched: $totalFetched, totalInserted: $totalInserted, '
      'newArticles: ${newArticles.length}, sources: ${results.length})';
}

/// Motor de sincronización concurrente con aislamiento estricto de fallos.
///
/// Garantiza que el fallo o timeout de una fuente (ej. DTV) no interrumpa ni
/// degrade la sincronización de las demás fuentes (ej. ABI o El Deber).
/// Aplica un límite de concurrencia para proteger el uso de batería y ancho de banda.
class MultiSourceSyncEngine {
  MultiSourceSyncEngine({
    required NewsSourceRegistry registry,
    this.maxConcurrency = 2,
    this.perSourceTimeout = const Duration(seconds: 10),
  }) : _registry = registry;

  final NewsSourceRegistry _registry;
  final int maxConcurrency;
  final Duration perSourceTimeout;

  /// Ejecuta la sincronización de todas las fuentes habilitadas en [_registry]
  /// con límite de concurrencia y tolerancia individual a fallos.
  Future<List<SourceSyncResult>> fetchAllSources({
    List<NewsSource>? targetSources,
  }) async {
    final sources = targetSources ?? _registry.getEnabledSources();
    if (sources.isEmpty) {
      return const <SourceSyncResult>[];
    }

    final results = List<SourceSyncResult?>.filled(sources.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= sources.length) return;
        final source = sources[index];
        results[index] = await _fetchSingleSourceIsolated(source);
      }
    }

    final workerCount = maxConcurrency.clamp(1, sources.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));

    return List<SourceSyncResult>.unmodifiable(
      results.whereType<SourceSyncResult>(),
    );
  }

  Future<SourceSyncResult> _fetchSingleSourceIsolated(NewsSource source) async {
    final startUtc = DateTime.now().toUtc();
    try {
      final articles = await source.fetchLatestArticles().timeout(
        perSourceTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Tiempo de espera agotado (${perSourceTimeout.inSeconds}s) al sincronizar con ${source.name}.',
          );
        },
      );

      return SourceSyncResult(
        sourceId: source.id,
        sourceName: source.name,
        fetched: articles.length,
        articles: articles,
        syncedAt: DateTime.now().toUtc(),
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '[MultiSourceSyncEngine] Error en fuente "${source.name}" (${source.id}): $e\n$stack',
        );
      }
      return SourceSyncResult(
        sourceId: source.id,
        sourceName: source.name,
        fetched: 0,
        articles: const <ArticleModel>[],
        error: e,
        syncedAt: startUtc,
      );
    }
  }
}

