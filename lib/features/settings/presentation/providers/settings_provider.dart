import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';
import 'package:nexusbo/services/background/background_task_service.dart';
import 'package:nexusbo/services/notifications/notification_service.dart';
import 'package:nexusbo/services/preferences/app_preferences_service.dart';

/// Provider de acceso al servicio de preferencias persistentes.
final appPreferencesProvider = Provider<AppPreferencesDataSource>((ref) {
  return AppPreferencesService();
});

/// Estado inmutable de las preferencias de Ajustes de NexusBO.
@immutable
class SettingsState {
  const SettingsState({
    this.isLoaded = false,
    this.backgroundSyncEnabled = true,
    this.notificationsEnabled = false,
    this.hourlyReportsEnabled = true,
    this.autoRefreshOnOpen = true,
    this.isWorkerScheduled = false,
    this.isRunningDebugSync = false,
    this.easterEggUnlocked = false,
  });

  final bool isLoaded;
  final bool backgroundSyncEnabled;
  final bool notificationsEnabled;
  final bool hourlyReportsEnabled;
  final bool autoRefreshOnOpen;
  final bool isWorkerScheduled;
  final bool isRunningDebugSync;
  final bool easterEggUnlocked;

  SettingsState copyWith({
    bool? isLoaded,
    bool? backgroundSyncEnabled,
    bool? notificationsEnabled,
    bool? hourlyReportsEnabled,
    bool? autoRefreshOnOpen,
    bool? isWorkerScheduled,
    bool? isRunningDebugSync,
    bool? easterEggUnlocked,
  }) {
    return SettingsState(
      isLoaded: isLoaded ?? this.isLoaded,
      backgroundSyncEnabled:
          backgroundSyncEnabled ?? this.backgroundSyncEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      hourlyReportsEnabled: hourlyReportsEnabled ?? this.hourlyReportsEnabled,
      autoRefreshOnOpen: autoRefreshOnOpen ?? this.autoRefreshOnOpen,
      isWorkerScheduled: isWorkerScheduled ?? this.isWorkerScheduled,
      isRunningDebugSync: isRunningDebugSync ?? this.isRunningDebugSync,
      easterEggUnlocked: easterEggUnlocked ?? this.easterEggUnlocked,
    );
  }
}

/// Notifier encargado de sincronizar las preferencias persistentes con el
/// permiso real de Android y el worker periódico de WorkManager.
class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    Future<void>.microtask(_loadAndReconcileSettings);
    return const SettingsState();
  }

  AppPreferencesDataSource get _preferences => ref.read(appPreferencesProvider);

  Future<void> _loadAndReconcileSettings() async {
    var savedEasterEgg = false;
    try {
      savedEasterEgg = await _preferences.getEasterEggUnlocked();
      state = state.copyWith(easterEggUnlocked: savedEasterEgg);
    } catch (_) {}

    try {
      final savedBackgroundSync = await _preferences.getBackgroundSyncEnabled();
      final savedNotifications = await _preferences.getNotificationsEnabled();
      final savedHourlyReports = await _preferences.getHourlyReportsEnabled();
      final savedAutoRefresh = await _preferences.getAutoRefreshOnOpen();

      var effectiveNotifications = savedNotifications;
      var workerScheduled = false;

      // 1. Reconciliar worker de fondo independientemente de las notificaciones
      if (savedBackgroundSync) {
        await BackgroundTaskService.instance.registerUniquePeriodicSync();
        workerScheduled = await BackgroundTaskService.instance
            .isPeriodicSyncScheduled();
      } else {
        await BackgroundTaskService.instance.cancelPeriodicSync();
      }

      // 2. Reconciliar permiso de notificaciones de Android
      if (savedNotifications) {
        final systemAllowed = await NotificationService.instance
            .areNotificationsAllowedBySystem();
        if (!systemAllowed) {
          // El usuario revocó el permiso desde los Ajustes de Android
          effectiveNotifications = false;
          await _preferences.setNotificationsEnabled(false);
        }
      }

      state = state.copyWith(
        isLoaded: true,
        backgroundSyncEnabled: savedBackgroundSync,
        notificationsEnabled: effectiveNotifications,
        hourlyReportsEnabled: savedHourlyReports,
        autoRefreshOnOpen: savedAutoRefresh,
        isWorkerScheduled: workerScheduled,
        easterEggUnlocked: savedEasterEgg,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NexusBO: Error al reconciliar preferencias de Ajustes: $e');
      }
      state = state.copyWith(
        isLoaded: true,
        easterEggUnlocked: savedEasterEgg,
      );
    }
  }

  /// Revalida el permiso del sistema al volver a la aplicación por si el
  /// usuario lo cambió en los Ajustes de Android.
  Future<void> refreshPermissionStatus() async {
    if (!state.isLoaded) return;
    if (state.notificationsEnabled) {
      final allowed = await NotificationService.instance
          .areNotificationsAllowedBySystem();
      if (!allowed) {
        await _preferences.setNotificationsEnabled(false);
        state = state.copyWith(notificationsEnabled: false);
      }
    }
  }

  /// Activa o desactiva la sincronización periódica en segundo plano (~60 min)
  /// mediante Android WorkManager de forma desacoplada de las notificaciones.
  Future<void> setBackgroundSyncEnabled(bool requestedValue) async {
    if (!requestedValue) {
      await _preferences.setBackgroundSyncEnabled(false);
      await BackgroundTaskService.instance.cancelPeriodicSync();
      state = state.copyWith(
        backgroundSyncEnabled: false,
        isWorkerScheduled: false,
      );
      return;
    }

    await _preferences.setBackgroundSyncEnabled(true);
    await BackgroundTaskService.instance.registerUniquePeriodicSync();
    final scheduled = await BackgroundTaskService.instance
        .isPeriodicSyncScheduled();
    state = state.copyWith(
      backgroundSyncEnabled: true,
      isWorkerScheduled: scheduled,
    );
  }

  /// Activa o desactiva las notificaciones de noticias en el canal `nexusbo_news`.
  ///
  /// Devuelve `true` si el estado solicitado quedó activo, o `false` si fue
  /// desactivado o el usuario rechazó el permiso de Android.
  Future<bool> setNotificationsEnabled(bool requestedValue) async {
    if (!requestedValue) {
      await _preferences.setNotificationsEnabled(false);
      state = state.copyWith(notificationsEnabled: false);
      return false;
    }

    final granted = await NotificationService.instance
        .requestPermissionFromUi();
    if (!granted) {
      await _preferences.setNotificationsEnabled(false);
      state = state.copyWith(notificationsEnabled: false);
      return false;
    }

    await _preferences.setNotificationsEnabled(true);
    state = state.copyWith(notificationsEnabled: true);
    return true;
  }

  /// Cambia la preferencia de emitir notificaciones para reportes horarios automáticos.
  Future<void> setHourlyReportsEnabled(bool enabled) async {
    await _preferences.setHourlyReportsEnabled(enabled);
    state = state.copyWith(hourlyReportsEnabled: enabled);
  }

  /// Cambia la preferencia de actualizar automáticamente el feed al abrir la app.
  Future<void> setAutoRefreshOnOpen(bool enabled) async {
    await _preferences.setAutoRefreshOnOpen(enabled);
    state = state.copyWith(autoRefreshOnOpen: enabled);
  }

  /// Ejecuta inmediatamente la misma lógica del worker de background (solo DEBUG)
  /// y recarga la vista desde SQLite al finalizar.
  Future<BackgroundSyncExecutionResult> runDebugBackgroundSyncNow() async {
    state = state.copyWith(isRunningDebugSync: true);
    try {
      final result = await BackgroundTaskService.instance
          .executeIsolatedBackgroundSync(isBackgroundIsolate: false);
      await ref.read(newsFeedProvider.notifier).reloadFromSqlite();
      return result;
    } finally {
      state = state.copyWith(isRunningDebugSync: false);
    }
  }

  /// Dispara una notificación de prueba para la última hora completa real (solo DEBUG).
  Future<bool> simulateHourlyReportNotification() async {
    var allowed = await NotificationService.instance
        .areNotificationsAllowedBySystem();
    if (!allowed) {
      allowed = await NotificationService.instance.requestPermissionFromUi();
    }
    if (!allowed) return false;

    return BackgroundTaskService.instance.processHourlyReportNow(force: true);
  }

  /// Procesa la evaluación de recordatorio horario (solo DEBUG).
  Future<bool> processHourlyReportNow({bool force = true}) async {
    return BackgroundTaskService.instance.processHourlyReportNow(force: force);
  }

  /// Envía una notificación de prueba inmediata en el canal `nexusbo_news`
  /// (solo DEBUG) sin insertar noticias ficticias en SQLite.
  Future<bool> sendDebugTestNotification() async {
    var allowed = await NotificationService.instance
        .areNotificationsAllowedBySystem();
    if (!allowed) {
      allowed = await NotificationService.instance.requestPermissionFromUi();
    }
    if (!allowed) return false;

    await NotificationService.instance.showDebugTestNotification();
    return true;
  }

  /// Persiste el estado de desbloqueo del secreto visual y actualiza el estado reactivo.
  Future<void> unlockEasterEgg() async {
    await _preferences.setEasterEggUnlocked(true);
    state = state.copyWith(easterEggUnlocked: true);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// Provider de conveniencia para consultar si el secreto está desbloqueado.
final easterEggUnlockedProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider.select((s) => s.easterEggUnlocked));
});
