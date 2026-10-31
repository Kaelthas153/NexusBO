import 'package:shared_preferences/shared_preferences.dart';

/// Contrato de preferencias persistentes de NexusBO para permitir inyección y
/// pruebas unitarias deterministas sin depender de canales nativos.
abstract interface class AppPreferencesDataSource {
  Future<bool> getNotificationsEnabled({bool reload = false});

  Future<void> setNotificationsEnabled(bool enabled);

  Future<bool> getAutoRefreshOnOpen({bool reload = false});

  Future<void> setAutoRefreshOnOpen(bool enabled);

  Future<bool> isCacheClearedPendingBaseline({bool reload = false});

  Future<void> setCacheClearedPendingBaseline(bool pending);

  // --- Sincronización en segundo plano ---
  Future<bool> getBackgroundSyncEnabled({bool reload = false});

  Future<void> setBackgroundSyncEnabled(bool enabled);

  // --- Protección Seed por Fuente ---
  Future<Set<String>> getSeededSourceIds({bool reload = false});

  Future<void> setSourceSeeded(String sourceId);

  Future<void> clearSeededSources();

  // --- Módulo de Reportes de Monitoreo ---

  Future<bool> getHourlyReportsEnabled({bool reload = false});

  Future<void> setHourlyReportsEnabled(bool enabled);

  Future<String?> getLastHourlyReportWindowNotified({bool reload = false});

  Future<void> setLastHourlyReportWindowNotified(String windowId);

  Future<bool> getReportSourcesModeAll({bool reload = false});

  Future<void> setReportSourcesModeAll(bool isAll);

  Future<List<String>> getReportSelectedSourceIds({bool reload = false});

  Future<void> setReportSelectedSourceIds(List<String> sourceIds);

  // --- Interacción Secreta ---
  Future<bool> getEasterEggUnlocked({bool reload = false});

  Future<void> setEasterEggUnlocked(bool unlocked);
}

/// Implementación de [AppPreferencesDataSource] respaldada por [SharedPreferences].
class AppPreferencesService implements AppPreferencesDataSource {
  AppPreferencesService({SharedPreferences? sharedPreferences})
    : _prefsInstance = sharedPreferences;

  static const String keyNotificationsEnabled = 'nexusbo_notifications_enabled';
  static const String keyBackgroundSyncEnabled = 'nexusbo_background_sync_enabled';
  static const String keyAutoRefreshOnOpen = 'nexusbo_auto_refresh_on_open';
  static const String keyCacheClearedPendingBaseline =
      'nexusbo_cache_cleared_pending_baseline';
  static const String keySeededSourceIds = 'nexusbo_seeded_source_ids';

  static const String keyHourlyReportsEnabled = 'nexusbo_hourly_reports_enabled';
  static const String keyLastHourlyReportWindowNotified =
      'nexusbo_last_hourly_report_window_notified';
  static const String keyReportSourcesModeAll = 'nexusbo_report_sources_mode_all';
  static const String keyReportSelectedSourceIds =
      'nexusbo_report_selected_source_ids';
  static const String keyEasterEggUnlocked = 'nexusbo_easter_egg_unlocked';

  SharedPreferences? _prefsInstance;

  Future<SharedPreferences> _getPrefs({bool reload = false}) async {
    final prefs = _prefsInstance ??= await SharedPreferences.getInstance();
    if (reload) {
      try {
        await prefs.reload();
      } catch (_) {
        // Ignorar si la plataforma de test no requiere reload.
      }
    }
    return prefs;
  }

  @override
  Future<bool> getNotificationsEnabled({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getBool(keyNotificationsEnabled) ?? false;
  }

  @override
  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyNotificationsEnabled, enabled);
  }

  @override
  Future<bool> getBackgroundSyncEnabled({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getBool(keyBackgroundSyncEnabled) ?? true;
  }

  @override
  Future<void> setBackgroundSyncEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyBackgroundSyncEnabled, enabled);
  }

  @override
  Future<Set<String>> getSeededSourceIds({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    final list = prefs.getStringList(keySeededSourceIds) ?? const <String>[];
    return list.map((e) => e.toLowerCase()).toSet();
  }

  @override
  Future<void> setSourceSeeded(String sourceId) async {
    final prefs = await _getPrefs();
    final set = (prefs.getStringList(keySeededSourceIds) ?? <String>[])
        .map((e) => e.toLowerCase())
        .toSet();
    set.add(sourceId.toLowerCase());
    await prefs.setStringList(keySeededSourceIds, set.toList());
  }

  @override
  Future<void> clearSeededSources() async {
    final prefs = await _getPrefs();
    await prefs.remove(keySeededSourceIds);
  }

  @override
  Future<bool> getAutoRefreshOnOpen({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getBool(keyAutoRefreshOnOpen) ?? true;
  }

  @override
  Future<void> setAutoRefreshOnOpen(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyAutoRefreshOnOpen, enabled);
  }

  @override
  Future<bool> isCacheClearedPendingBaseline({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getBool(keyCacheClearedPendingBaseline) ?? false;
  }

  @override
  Future<void> setCacheClearedPendingBaseline(bool pending) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyCacheClearedPendingBaseline, pending);
  }

  @override
  Future<bool> getHourlyReportsEnabled({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getBool(keyHourlyReportsEnabled) ?? true;
  }

  @override
  Future<void> setHourlyReportsEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyHourlyReportsEnabled, enabled);
  }

  @override
  Future<String?> getLastHourlyReportWindowNotified({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getString(keyLastHourlyReportWindowNotified);
  }

  @override
  Future<void> setLastHourlyReportWindowNotified(String windowId) async {
    final prefs = await _getPrefs();
    await prefs.setString(keyLastHourlyReportWindowNotified, windowId);
  }

  @override
  Future<bool> getReportSourcesModeAll({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getBool(keyReportSourcesModeAll) ?? true;
  }

  @override
  Future<void> setReportSourcesModeAll(bool isAll) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyReportSourcesModeAll, isAll);
  }

  @override
  Future<List<String>> getReportSelectedSourceIds({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getStringList(keyReportSelectedSourceIds) ?? const <String>[];
  }

  @override
  Future<void> setReportSelectedSourceIds(List<String> sourceIds) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(keyReportSelectedSourceIds, sourceIds);
  }

  @override
  Future<bool> getEasterEggUnlocked({bool reload = false}) async {
    final prefs = await _getPrefs(reload: reload);
    return prefs.getBool(keyEasterEggUnlocked) ?? false;
  }

  @override
  Future<void> setEasterEggUnlocked(bool unlocked) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyEasterEggUnlocked, unlocked);
  }
}

