import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexusbo/core/constants/api_constants.dart';
import 'package:nexusbo/core/errors/app_exception.dart';

/// Cliente HTTP sencillo y robusto basado en [Dio] para consumo de feeds RSS.
class DioClient {
  DioClient({Dio? dio}) : _dio = dio ?? _createDefaultDio();

  final Dio _dio;

  static Dio _createDefaultDio() {
    return Dio(
      BaseOptions(
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        sendTimeout: ApiConstants.sendTimeout,
        responseType: ResponseType.plain,
        headers: const <String, Object>{
          'User-Agent': ApiConstants.userAgent,
          'Accept': ApiConstants.acceptHeader,
        },
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );
  }

  /// Descarga el cuerpo texto/XML/JSON desde [url] manejando errores de red,
  /// timeouts, códigos HTTP inválidos y respuestas vacías.
  Future<String> getRawString(
    String url, {
    Map<String, Object>? headers,
    Duration? timeout,
  }) async {
    final normalizedUrl = _normalizeAbiUrl(url);
    try {
      final response = await _dio.get<String>(
        normalizedUrl,
        options: Options(
          headers: headers,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      final statusCode = response.statusCode;

      if (statusCode != 200) {
        throw NetworkException(
          'El servidor respondió con estado HTTP ${statusCode ?? "desconocido"}.',
          statusCode: statusCode,
        );
      }

      final body = response.data;
      if (body == null || body.trim().isEmpty) {
        throw const NetworkException(
          'El servidor devolvió una respuesta vacía.',
        );
      }

      return body;
    } on AppException {
      rethrow;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[DioClient] Error al consultar $normalizedUrl: ${e.type} - ${e.message}',
        );
      }
      throw _mapDioException(e);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DioClient] Error inesperado en petición HTTP: $e');
      }
      throw NetworkException(
        'No fue posible completar la conexión con la fuente de noticias.',
        cause: e,
      );
    }
  }

  /// Descarga el cuerpo texto/XML desde [url] manejando errores de red,
  /// timeouts, códigos HTTP inválidos y respuestas vacías.
  Future<String> getRawXml(String url) => getRawString(url);

  /// Intenta descargar el HTML de la página de un artículo individual para
  /// extraer su imagen destacada (`og:image` / `wp-post-image`).
  ///
  /// Es tolerante a fallos: si ocurre cualquier error o timeout, devuelve `null`
  /// para no interrumpir la sincronización del feed RSS.
  Future<String?> tryGetArticleHtml(
    String url, {
    Map<String, Object>? headers,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final normalizedUrl = _normalizeAbiUrl(url);
    if (normalizedUrl.isEmpty) return null;

    try {
      final response = await _dio.get<String>(
        normalizedUrl,
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: headers ??
              const <String, Object>{
                'User-Agent': ApiConstants.userAgent,
                'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
              },
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data;
      }
    } catch (_) {
      // Silencioso por diseño: la falta de HTML secundario no debe fallar el RSS
    }
    return null;
  }

  static String _normalizeAbiUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri != null && uri.host.toLowerCase() == 'www.abi.bo') {
      return uri.replace(host: 'abi.bo').toString();
    }
    return rawUrl.trim();
  }

  static NetworkException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return NetworkException(
          'Tiempo de espera agotado al conectar con ABI.',
          statusCode: e.response?.statusCode,
          cause: e,
        );
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return NetworkException(
          'Respuesta inválida del servidor (HTTP ${code ?? "error"}).',
          statusCode: code,
          cause: e,
        );
      case DioExceptionType.connectionError:
        return NetworkException(
          'Sin conexión disponible con el servidor de noticias.',
          cause: e,
        );
      case DioExceptionType.badCertificate:
        return NetworkException(
          'Error de certificado de seguridad al conectar con la fuente.',
          cause: e,
        );
      case DioExceptionType.cancel:
        return NetworkException(
          'La solicitud fue cancelada.',
          cause: e,
        );
      case DioExceptionType.unknown:
        return NetworkException(
          'Error de red al obtener las últimas noticias.',
          cause: e,
        );
    }
  }
}
