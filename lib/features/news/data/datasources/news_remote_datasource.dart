import 'package:nexusbo/features/news/data/models/article_model.dart';

/// Contrato de la fuente remota de noticias.
/// Diseñado para permitir el reemplazo futuro del lector RSS por una API REST
/// propia sin modificar el repositorio, SQLite ni la interfaz de usuario.
abstract interface class NewsRemoteDataSource {
  Future<List<ArticleModel>> fetchLatestArticles();
}

