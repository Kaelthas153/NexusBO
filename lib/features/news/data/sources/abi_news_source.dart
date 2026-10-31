import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/network/dio_client.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';
import 'package:nexusbo/features/news/data/datasources/rss_news_remote_datasource.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/sources/news_source.dart';

/// Implementación de [NewsSource] para la Agencia Boliviana de Información (ABI).
///
/// Consume el feed RSS 2.0 oficial (`https://abi.bo/feed/`), extrayendo el contenido
/// completo desde `content:encoded`, resolviendo imágenes destacadas (`og:image`)
/// y normalizando las categorías al conjunto canónico mediante [CategoryMapper].
class AbiNewsSource implements NewsSource {
  AbiNewsSource({
    required DioClient dioClient,
    String feedUrl = ApiConstants.abiFeedUrl,
    bool resolveFeaturedImagesFromArticlePages = true,
  }) : _rssDataSource = RssNewsRemoteDataSource(
         dioClient: dioClient,
         feedUrl: feedUrl,
         resolveFeaturedImagesFromArticlePages:
             resolveFeaturedImagesFromArticlePages,
       );

  final RssNewsRemoteDataSource _rssDataSource;

  @override
  String get id => ApiConstants.abiSourceId; // 'abi'

  @override
  String get name => ApiConstants.abiSourceName; // 'ABI'

  @override
  int get sortOrder => 1;

  @override
  Future<List<ArticleModel>> fetchLatestArticles() async {
    final rawArticles = await _rssDataSource.fetchLatestArticles();
    return rawArticles.map((m) {
      final canonicalCategory = CategoryMapper.toCanonical(m.category);
      return m.copyWith(category: canonicalCategory);
    }).toList(growable: false);
  }

  /// Método expuesto para pruebas deterministas offline con fixtures XML.
  List<ArticleModel> parseRssXml(
    String rawXml, {
    DateTime? fetchedAtOverrideUtc,
    Map<String, String>? articlePageHtmlByUrl,
  }) {
    final rawArticles = _rssDataSource.parseRssXml(
      rawXml,
      fetchedAtOverrideUtc: fetchedAtOverrideUtc,
      articlePageHtmlByUrl: articlePageHtmlByUrl,
    );
    return rawArticles.map((m) {
      final canonicalCategory = CategoryMapper.toCanonical(m.category);
      return m.copyWith(category: canonicalCategory);
    }).toList(growable: false);
  }
}

