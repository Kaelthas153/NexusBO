/// Jerarquía concisa de excepciones de dominio/datos para NexusBO.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Error de red al consultar una fuente remota (timeout, sin conexión,
/// estado HTTP inválido o respuesta vacía).
final class NetworkException extends AppException {
  const NetworkException(
    super.message, {
    this.statusCode,
    super.cause,
  });

  final int? statusCode;
}

/// Error al interpretar el documento XML/RSS de la fuente remota.
final class ParseException extends AppException {
  const ParseException(super.message, {super.cause});
}

/// Error al realizar operaciones sobre la base de datos SQLite local.
final class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.cause});
}

