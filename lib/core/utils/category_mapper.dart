/// Utilidad central de normalización y homogeneización de categorías de noticias
/// provenientes de múltiples medios bolivianos hacia un conjunto canónico.
abstract final class CategoryMapper {
  /// Categorías canónicas estándar de NexusBO en minúsculas sin tildes.
  static const String canonicalPolitica = 'politica';
  static const String canonicalEconomia = 'economia';
  static const String canonicalSeguridad = 'seguridad';
  static const String canonicalSociedad = 'sociedad';
  static const String canonicalDeportes = 'deportes';
  static const String canonicalCultura = 'cultura';
  static const String canonicalGeneral = 'general';

  /// Lista ordenada de todas las categorías canónicas disponibles.
  static const List<String> canonicalCategories = <String>[
    canonicalPolitica,
    canonicalEconomia,
    canonicalSeguridad,
    canonicalSociedad,
    canonicalDeportes,
    canonicalCultura,
    canonicalGeneral,
  ];

  /// Nombres de presentación editorial para la interfaz de usuario.
  static const Map<String, String> _displayNames = <String, String>{
    canonicalPolitica: 'Política',
    canonicalEconomia: 'Economía',
    canonicalSeguridad: 'Seguridad',
    canonicalSociedad: 'Sociedad',
    canonicalDeportes: 'Deportes',
    canonicalCultura: 'Cultura',
    canonicalGeneral: 'General',
  };

  /// Normaliza una cadena de categoría sin procesar (de cualquier medio o filtro UI)
  /// a una categoría canónica en minúsculas sin tilde.
  static String toCanonical(String? rawCategory) {
    if (rawCategory == null) return canonicalGeneral;
    var cleaned = rawCategory.trim().toLowerCase();
    if (cleaned.isEmpty) return canonicalGeneral;

    // Remover slashes iniciales o finales (e.g. "/pais/" -> "pais")
    cleaned = cleaned.replaceAll(RegExp(r'^/+|/+$'), '');

    // Reemplazos de tildes para simplificar comparaciones
    final normalized = cleaned
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');

    // 1. Política
    if (normalized.contains('politica') ||
        normalized.contains('gobierno') ||
        normalized.contains('parlamento') ||
        normalized.contains('asamblea') ||
        normalized.contains('legislativ')) {
      return canonicalPolitica;
    }

    // 2. Economía
    if (normalized.contains('economia') ||
        normalized.contains('finanzas') ||
        normalized.contains('negocios') ||
        normalized.contains('mercado') ||
        normalized.contains('tribut') ||
        normalized.contains('banco')) {
      return canonicalEconomia;
    }

    // 3. Seguridad / Policial
    if (normalized.contains('seguridad') ||
        normalized.contains('policia') ||
        normalized.contains('policial') ||
        normalized.contains('fiscalia') ||
        normalized.contains('judicial') ||
        normalized.contains('justicia') ||
        normalized.contains('crimen') ||
        normalized.contains('suceso')) {
      return canonicalSeguridad;
    }

    // 4. Deportes
    if (normalized.contains('deporte') ||
        normalized.contains('marcas') ||
        normalized.contains('futbol') ||
        normalized.contains('liga')) {
      return canonicalDeportes;
    }

    // 5. Cultura / Entretenimiento
    if (normalized.contains('cultur') ||
        normalized.contains('entretenimiento') ||
        normalized.contains('farandula') ||
        normalized.contains('espectaculo') ||
        normalized.contains('arte') ||
        normalized.contains('voces')) {
      return canonicalCultura;
    }

    // 6. Sociedad / Nacional / País / Ciudades / Departamentos
    if (normalized.contains('sociedad') ||
        normalized.contains('nacional') ||
        normalized.contains('pais') ||
        normalized.contains('santa-cruz') ||
        normalized.contains('santa cruz') ||
        normalized.contains('sociales') ||
        normalized.contains('ciudad') ||
        normalized.contains('comunidad') ||
        normalized.contains('salud') ||
        normalized.contains('educacion') ||
        normalized.contains('local') ||
        normalized.contains('tarija') ||
        normalized.contains('la paz') ||
        normalized.contains('cochabamba')) {
      return canonicalSociedad;
    }

    // 7. Mundo / Opinión / General
    return canonicalGeneral;
  }

  /// Devuelve el nombre de visualización con mayúsculas y acentos correctos
  /// (e.g. `'politica'` -> `'Política'`).
  static String toDisplay(String? category) {
    final canonical = toCanonical(category);
    return _displayNames[canonical] ?? 'General';
  }
}

