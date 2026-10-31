import 'dart:convert';

import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/features/news/domain/entities/article.dart';
import 'package:nexusbo/services/database/tables/articles_table.dart';

/// Modelo de datos encargado del mapeo entre la entidad de dominio [Article]
/// y la representación relacional en SQLite (`Map<String, Object?>`).
class ArticleModel {
  ArticleModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.contentPlain,
    required this.url,
    String? imageUrl,
    List<String>? imageUrls,
    required this.author,
    required this.sourceId,
    required this.sourceName,
    required this.category,
    required List<String> tags,
    required DateTime publishedAt,
    required DateTime fetchedAt,
    this.isFavorite = false,
    DateTime? favoritedAt,
    this.isRead = false,
  }) : imageUrl = _resolveMainImage(imageUrl, imageUrls),
       imageUrls = List<String>.unmodifiable(
         _resolveAllImages(imageUrl, imageUrls),
       ),
       tags = List<String>.unmodifiable(tags),
       publishedAt = BoliviaDateFormatter.ensureUtc(publishedAt),
       fetchedAt = BoliviaDateFormatter.ensureUtc(fetchedAt),
       favoritedAt = favoritedAt != null
           ? BoliviaDateFormatter.ensureUtc(favoritedAt)
           : null;

  final String id;
  final String title;
  final String summary;
  final String contentPlain;
  final String url;
  final String? imageUrl;
  final List<String> imageUrls;
  final String author;
  final String sourceId;
  final String sourceName;
  final String category;
  final List<String> tags;
  final DateTime publishedAt;
  final DateTime fetchedAt;
  final bool isFavorite;
  final DateTime? favoritedAt;
  final bool isRead;

  /// Construye un [ArticleModel] a partir de una fila de SQLite.
  factory ArticleModel.fromSqliteMap(Map<String, Object?> map) {
    final rawImageUrl = map[ArticlesTable.colImageUrl] as String?;
    final normalizedImageUrl =
        (rawImageUrl != null && rawImageUrl.trim().isNotEmpty)
        ? rawImageUrl.trim()
        : null;

    final decodedImageUrls = _decodeStringListJson(
      map[ArticlesTable.colImageUrlsJson],
    );

    final publishedAtMs = _readInt(
      map[ArticlesTable.colPublishedAt],
      fallback: 0,
    );
    final fetchedAtMs = _readInt(
      map[ArticlesTable.colFetchedAt],
      fallback: publishedAtMs,
    );

    return ArticleModel(
      id: (map[ArticlesTable.colId] as String?) ?? '',
      title: (map[ArticlesTable.colTitle] as String?) ?? '',
      summary: (map[ArticlesTable.colSummary] as String?) ?? '',
      contentPlain: (map[ArticlesTable.colContentPlain] as String?) ?? '',
      url: (map[ArticlesTable.colUrl] as String?) ?? '',
      imageUrl: normalizedImageUrl,
      imageUrls: decodedImageUrls,
      author: (map[ArticlesTable.colAuthor] as String?) ?? 'Redacción Central',
      sourceId: (map[ArticlesTable.colSourceId] as String?) ?? 'abi',
      sourceName: (map[ArticlesTable.colSourceName] as String?) ?? 'ABI',
      category: (map[ArticlesTable.colCategory] as String?) ?? 'General',
      tags: _decodeStringListJson(map[ArticlesTable.colTagsJson]),
      publishedAt: BoliviaDateFormatter.fromSqliteTimestamp(publishedAtMs),
      fetchedAt: BoliviaDateFormatter.fromSqliteTimestamp(fetchedAtMs),
      isFavorite: _readBool(map[ArticlesTable.colIsFavorite]),
      favoritedAt: BoliviaDateFormatter.fromSqliteTimestampOrNull(
        map[ArticlesTable.colFavoritedAt],
      ),
      isRead: _readBool(map[ArticlesTable.colIsRead]),
    );
  }

  /// Construye un [ArticleModel] desde la entidad de dominio [Article].
  factory ArticleModel.fromEntity(Article entity) {
    return ArticleModel(
      id: entity.id,
      title: entity.title,
      summary: entity.summary,
      contentPlain: entity.contentPlain,
      url: entity.url,
      imageUrl: entity.imageUrl,
      imageUrls: entity.imageUrls,
      author: entity.author,
      sourceId: entity.sourceId,
      sourceName: entity.sourceName,
      category: entity.category,
      tags: entity.tags,
      publishedAt: entity.publishedAt,
      fetchedAt: entity.fetchedAt,
      isFavorite: entity.isFavorite,
      favoritedAt: entity.favoritedAt,
      isRead: entity.isRead,
    );
  }

  /// Convierte este [ArticleModel] a un `Map<String, Object?>` apto para SQLite.
  Map<String, Object?> toSqliteMap() {
    return <String, Object?>{
      ArticlesTable.colId: id,
      ArticlesTable.colTitle: title,
      ArticlesTable.colSummary: summary,
      ArticlesTable.colContentPlain: contentPlain,
      ArticlesTable.colUrl: url,
      ArticlesTable.colImageUrl: imageUrl,
      ArticlesTable.colImageUrlsJson: jsonEncode(imageUrls),
      ArticlesTable.colAuthor: author,
      ArticlesTable.colSourceId: sourceId,
      ArticlesTable.colSourceName: sourceName,
      ArticlesTable.colCategory: category,
      ArticlesTable.colTagsJson: jsonEncode(tags),
      ArticlesTable.colPublishedAt: BoliviaDateFormatter.toSqliteTimestamp(
        publishedAt,
      ),
      ArticlesTable.colFetchedAt: BoliviaDateFormatter.toSqliteTimestamp(
        fetchedAt,
      ),
      ArticlesTable.colIsFavorite: isFavorite ? 1 : 0,
      ArticlesTable.colFavoritedAt: BoliviaDateFormatter.toSqliteTimestampOrNull(
        favoritedAt,
      ),
      ArticlesTable.colIsRead: isRead ? 1 : 0,
    };
  }

  /// Devuelve la lista ordenada de parámetros posicionales para
  /// [ArticlesTable.upsertArticleSql].
  List<Object?> toUpsertSqlArgs() {
    return <Object?>[
      id,
      title,
      summary,
      contentPlain,
      url,
      imageUrl,
      jsonEncode(imageUrls),
      author,
      sourceId,
      sourceName,
      category,
      jsonEncode(tags),
      BoliviaDateFormatter.toSqliteTimestamp(publishedAt),
      BoliviaDateFormatter.toSqliteTimestamp(fetchedAt),
      isFavorite ? 1 : 0,
      BoliviaDateFormatter.toSqliteTimestampOrNull(favoritedAt),
      isRead ? 1 : 0,
    ];
  }

  /// Convierte el modelo de datos en la entidad de dominio inmutable [Article].
  Article toEntity() {
    return Article(
      id: id,
      title: title,
      summary: summary,
      contentPlain: contentPlain,
      url: url,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      author: author,
      sourceId: sourceId,
      sourceName: sourceName,
      category: category,
      tags: tags,
      publishedAt: publishedAt,
      fetchedAt: fetchedAt,
      isFavorite: isFavorite,
      favoritedAt: favoritedAt,
      isRead: isRead,
    );
  }

  ArticleModel copyWith({
    String? id,
    String? title,
    String? summary,
    String? contentPlain,
    String? url,
    String? imageUrl,
    List<String>? imageUrls,
    bool clearImageUrl = false,
    String? author,
    String? sourceId,
    String? sourceName,
    String? category,
    List<String>? tags,
    DateTime? publishedAt,
    DateTime? fetchedAt,
    bool? isFavorite,
    DateTime? favoritedAt,
    bool clearFavoritedAt = false,
    bool? isRead,
  }) {
    return ArticleModel(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      contentPlain: contentPlain ?? this.contentPlain,
      url: url ?? this.url,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      imageUrls: clearImageUrl
          ? const <String>[]
          : (imageUrls ?? this.imageUrls),
      author: author ?? this.author,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      publishedAt: publishedAt ?? this.publishedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      favoritedAt: clearFavoritedAt ? null : (favoritedAt ?? this.favoritedAt),
      isRead: isRead ?? this.isRead,
    );
  }

  static String? _resolveMainImage(String? primary, List<String>? all) {
    final cleanPrimary = primary?.trim();
    if (cleanPrimary != null && cleanPrimary.isNotEmpty) {
      return cleanPrimary;
    }
    if (all != null) {
      for (final item in all) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
    return null;
  }

  static List<String> _resolveAllImages(String? primary, List<String>? all) {
    final result = <String>[];
    final cleanPrimary = primary?.trim();
    if (cleanPrimary != null && cleanPrimary.isNotEmpty) {
      result.add(cleanPrimary);
    }
    if (all != null) {
      for (final item in all) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty && !result.contains(trimmed)) {
          result.add(trimmed);
        }
      }
    }
    return result;
  }

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _readBool(Object? value) {
    if (value is int) return value == 1;
    if (value is bool) return value;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  static List<String> _decodeStringListJson(Object? rawJson) {
    if (rawJson == null) return const <String>[];
    if (rawJson is List) {
      return rawJson
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    if (rawJson is String && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          return decoded
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
        }
      } on FormatException {
        return const <String>[];
      }
    }
    return const <String>[];
  }
}
