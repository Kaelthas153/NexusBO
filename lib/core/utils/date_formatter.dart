import 'package:intl/intl.dart';

/// Utilidades de fechas para persistencia UTC, parseo RFC-822 de RSS y
/// presentación en hora local de Bolivia (UTC-4).
///
/// Regla arquitectónica:
/// - Toda persistencia en SQLite utiliza milisegundos UTC desde epoch.
/// - La conversión a hora de Bolivia (BOT, UTC-4) ocurre exclusivamente al
///   formatear texto para la interfaz de usuario.
abstract final class BoliviaDateFormatter {
  static const Duration _boliviaUtcOffset = Duration(hours: -4);

  static const List<String> _weekdaysEs = <String>[
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  static const List<String> _monthsEs = <String>[
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  // ---------------------------------------------------------------------------
  // CONVERSIÓN UTC Y SQLITE
  // ---------------------------------------------------------------------------

  /// Garantiza que el [DateTime] esté en UTC.
  static DateTime ensureUtc(DateTime dateTime) => dateTime.toUtc();

  /// Convierte un [DateTime] a timestamp entero UTC (millisecondsSinceEpoch)
  /// para almacenamiento en SQLite.
  static int toSqliteTimestamp(DateTime dateTime) {
    return dateTime.toUtc().millisecondsSinceEpoch;
  }

  /// Convierte un [DateTime] opcional a timestamp entero UTC o `null`.
  static int? toSqliteTimestampOrNull(DateTime? dateTime) {
    return dateTime?.toUtc().millisecondsSinceEpoch;
  }

  /// Recupera un [DateTime] en UTC desde el valor entero almacenado en SQLite.
  static DateTime fromSqliteTimestamp(int millisecondsSinceEpochUtc) {
    return DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpochUtc,
      isUtc: true,
    );
  }

  /// Recupera un [DateTime] en UTC o `null` desde un valor opcional de SQLite.
  static DateTime? fromSqliteTimestampOrNull(Object? rawValue) {
    if (rawValue == null) return null;
    if (rawValue is int) {
      return fromSqliteTimestamp(rawValue);
    }
    if (rawValue is num) {
      return fromSqliteTimestamp(rawValue.toInt());
    }
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      final parsedInt = int.tryParse(rawValue.trim());
      if (parsedInt != null) {
        return fromSqliteTimestamp(parsedInt);
      }
      final parsedIso = DateTime.tryParse(rawValue.trim());
      return parsedIso?.toUtc();
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // PARSEO RFC-822 PARA RSS (PREPARADO PARA ETAPA 3 - ABI)
  // ---------------------------------------------------------------------------

  static final RegExp _rfc822Regex = RegExp(
    r'^(?:[A-Za-z]{3},\s*)?(\d{1,2}\s+[A-Za-z]{3}\s+\d{4}\s+\d{2}:\d{2}(?::\d{2})?)\s*([+-]\d{4}|[A-Za-z]+)?$',
  );

  /// Parsea una fecha estándar RFC-822 / RFC-1123 proveniente de un feed RSS
  /// en inglés (ej. `"Sat, 31 Oct 2026 02:05:20 +0000"`) usando locale `en_US`
  /// y devuelve el instante exacto en UTC.
  ///
  /// Si el texto no puede ser interpretado, devuelve [fallbackUtc] o lanza
  /// [FormatException] si [fallbackUtc] es `null`.
  static DateTime parseRssRfc822Utc(
    String rawRssDate, {
    DateTime? fallbackUtc,
  }) {
    final cleaned = rawRssDate.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      if (fallbackUtc != null) return fallbackUtc.toUtc();
      throw const FormatException('Empty RSS date string');
    }

    final match = _rfc822Regex.firstMatch(cleaned);
    if (match != null) {
      final dateTimePart = match.group(1)!;
      final tzPart = match.group(2) ?? '+0000';

      try {
        final hasSeconds = dateTimePart.split(':').length == 3;
        final pattern = hasSeconds
            ? 'dd MMM yyyy HH:mm:ss'
            : 'dd MMM yyyy HH:mm';
        final parsedUtc = DateFormat(pattern, 'en_US').parseUtc(dateTimePart);
        final offset = _parseTimeZoneOffset(tzPart);
        return parsedUtc.subtract(offset);
      } on FormatException {
        // Continúa al intento alternativo ISO-8601
      }
    }

    final isoAttempt = DateTime.tryParse(cleaned);
    if (isoAttempt != null) {
      return isoAttempt.toUtc();
    }

    if (fallbackUtc != null) {
      return fallbackUtc.toUtc();
    }
    throw FormatException('Invalid RFC-822 RSS date: "$rawRssDate"');
  }

  static Duration _parseTimeZoneOffset(String tzToken) {
    final token = tzToken.trim().toUpperCase();
    if (token.isEmpty || token == 'UTC' || token == 'GMT' || token == 'Z') {
      return Duration.zero;
    }
    if (token == 'BOT') {
      return _boliviaUtcOffset;
    }

    final numericMatch = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(token);
    if (numericMatch != null) {
      final sign = numericMatch.group(1) == '-' ? -1 : 1;
      final hours = int.parse(numericMatch.group(2)!);
      final minutes = int.parse(numericMatch.group(3)!);
      return Duration(
        hours: sign * hours,
        minutes: sign * minutes,
      );
    }
    return Duration.zero;
  }

  // ---------------------------------------------------------------------------
  // PRESENTACIÓN EN HORA LOCAL DE BOLIVIA (UTC-4)
  // ---------------------------------------------------------------------------

  /// Retorna la diferencia de zona horaria oficial de Bolivia (-04:00).
  static const Duration boliviaUtcOffset = _boliviaUtcOffset;

  /// Retorna el instante actual en hora oficial de Bolivia (UTC-4).
  static DateTime nowInBolivia({DateTime? referenceUtc}) {
    return toBoliviaTime(referenceUtc ?? DateTime.now().toUtc());
  }

  /// Convierte una fecha y hora local de Bolivia (UTC-4) a su equivalente exacto en UTC.
  static DateTime boliviaTimeToUtc(DateTime boliviaDateTime) {
    return DateTime.utc(
      boliviaDateTime.year,
      boliviaDateTime.month,
      boliviaDateTime.day,
      boliviaDateTime.hour,
      boliviaDateTime.minute,
      boliviaDateTime.second,
      boliviaDateTime.millisecond,
    ).subtract(_boliviaUtcOffset);
  }

  /// Convierte cualquier [DateTime] a su representación en hora oficial de
  /// Bolivia (UTC-4).
  static DateTime toBoliviaTime(DateTime timestampUtc) {
    final utc = timestampUtc.toUtc();
    return utc.add(_boliviaUtcOffset);
  }

  /// Formatea una hora en formato am/pm de 12 horas (ej. `08:00 am`, `11:30 pm`).
  static String format12Hour(DateTime boliviaDateTime) {
    final hour = boliviaDateTime.hour;
    final minute = boliviaDateTime.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'am' : 'pm';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final hourStr = hour12.toString().padLeft(2, '0');
    return '$hourStr:$minute $period';
  }

  /// Formatea una fecha como `DD/MM/YYYY` (ej. `27/10/2026`).
  static String formatDayMonthYear(DateTime boliviaDateTime) {
    final day = boliviaDateTime.day.toString().padLeft(2, '0');
    final month = boliviaDateTime.month.toString().padLeft(2, '0');
    final year = boliviaDateTime.year;
    return '$day/$month/$year';
  }

  /// Formato de cabecera editorial: ej. "VIERNES, 30 DE OCTUBRE".
  static String formatEditorialHeader(DateTime timestampUtc) {
    final bolivia = toBoliviaTime(timestampUtc);
    final weekday = _weekdaysEs[bolivia.weekday - 1];
    final month = _monthsEs[bolivia.month - 1];
    return '$weekday, ${bolivia.day} de $month'.toUpperCase();
  }

  /// Formato compacto para el feed: ej. "Hace 18 min", "Hace 3 h" o "30 oct · 19:05".
  static String formatFeedTimestamp(
    DateTime publishedAtUtc, {
    DateTime? referenceUtc,
  }) {
    final nowUtc = (referenceUtc ?? DateTime.now()).toUtc();
    final pubUtc = publishedAtUtc.toUtc();
    final diff = nowUtc.difference(pubUtc);

    if (diff.inMinutes < 1) {
      return 'Ahora';
    }
    if (diff.inMinutes < 60) {
      return 'Hace ${diff.inMinutes} min';
    }
    if (diff.inHours < 12) {
      return 'Hace ${diff.inHours} h';
    }

    final bolivia = toBoliviaTime(pubUtc);
    final monthShort = _monthsEs[bolivia.month - 1].substring(0, 3);
    final timeStr = DateFormat('HH:mm').format(bolivia);
    return '${bolivia.day} $monthShort · $timeStr';
  }

  /// Formato completo para el detalle de un artículo en hora de Bolivia (BOT).
  static String formatFullArticleDate(DateTime publishedAtUtc) {
    final bolivia = toBoliviaTime(publishedAtUtc);
    final month = _monthsEs[bolivia.month - 1];
    final timeStr = DateFormat('HH:mm').format(bolivia);
    return '${bolivia.day} de $month de ${bolivia.year} · $timeStr BOT';
  }
}
