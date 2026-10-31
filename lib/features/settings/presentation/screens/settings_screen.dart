import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/app/theme/theme_mode_provider.dart';
import 'package:nexusbo/core/widgets/editorial_divider.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';
import 'package:nexusbo/features/settings/presentation/providers/settings_provider.dart';
import 'package:nexusbo/services/background/background_task_service.dart';

/// Pantalla de Ajustes conectada a preferencias persistentes, permisos de
/// notificaciones locales (Android 13+) y programación de Android WorkManager.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _handleBackgroundSyncToggle(
    BuildContext context,
    WidgetRef ref,
    bool requestedValue,
  ) async {
    await ref
        .read(settingsProvider.notifier)
        .setBackgroundSyncEnabled(requestedValue);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            requestedValue
                ? 'Sincronización en segundo plano activada con Android WorkManager.'
                : 'Sincronización en segundo plano desactivada.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _handleNotificationsToggle(
    BuildContext context,
    WidgetRef ref,
    bool requestedValue,
  ) async {
    final enabled = await ref
        .read(settingsProvider.notifier)
        .setNotificationsEnabled(requestedValue);
    if (!context.mounted) return;

    final String message;
    if (requestedValue && enabled) {
      message = 'Notificaciones de noticias activadas.';
    } else if (requestedValue && !enabled) {
      message = 'Permiso de notificaciones denegado en Android.';
    } else {
      message = 'Notificaciones de noticias desactivadas.';
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _handleDebugBackgroundSync(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await ref
        .read(settingsProvider.notifier)
        .runDebugBackgroundSyncNow();
    if (!context.mounted) return;

    final String summary;
    switch (result.outcome) {
      case BackgroundTaskOutcome.success:
        if (result.wasInitialOrPostClearSeed) {
          summary =
              'Sync background OK (semilla inicial/post-borrado): '
              '${result.fetchedCount} recibidas · ${result.insertedCount} guardadas · '
              '0 notificadas (anti-spam activo).';
        } else {
          summary =
              'Sync background OK: ${result.fetchedCount} recibidas · '
              '${result.insertedCount} nuevas · '
              '${result.notifiedArticlesCount} notificadas · '
              '${result.prunedCount} depuradas.';
        }
      case BackgroundTaskOutcome.retry:
        summary =
            'Sync background sin red (WorkManager -> retry): '
            '${result.errorMessage ?? "Error temporal"}. Datos locales intactos.';
      case BackgroundTaskOutcome.failure:
        summary =
            'Sync background falló sin afectar SQLite: '
            '${result.errorMessage ?? "Error de formato"}.';
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(summary),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _handleDebugTestNotification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final sent = await ref
        .read(settingsProvider.notifier)
        .sendDebugTestNotification();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Notificación de prueba enviada al canal nexusbo_news.'
                : 'No se pudo mostrar la notificación (permiso de Android no concedido).',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _handleSimulateHourlyReport(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final sent = await ref
        .read(settingsProvider.notifier)
        .simulateHourlyReportNotification();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Notificación de reporte horario enviada al canal nexusbo_reports.'
                : 'No se pudo emitir la notificación (permiso no concedido o sin noticias).',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _handleProcessHourlyReportNow(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final processed = await ref
        .read(settingsProvider.notifier)
        .processHourlyReportNow(force: true);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            processed
                ? 'Recordatorio horario evaluado y notificado con éxito.'
                : 'Evaluación completada (sin novedades o ventana ya notificada).',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;
    final currentThemeMode = ref.watch(themeModeProvider);
    final cachedCount = ref.watch(newsFeedProvider).totalCachedCount;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PREFERENCIAS DE EDICIÓN',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ajustes',
                    style: textTheme.displaySmall,
                  ),
                ],
              ),
            ),
            const EditorialDivider(),

            // -----------------------------------------------------------------
            // SECCIÓN 1: TEMA
            // -----------------------------------------------------------------
            const _SectionHeader(title: 'APARIENCIA Y TEMA'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Modo de visualización',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Adapta la paleta editorial para lectura diurna o nocturna.',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  _ThemeModeSelector(
                    selectedMode: currentThemeMode,
                    onChanged: (mode) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    },
                  ),
                ],
              ),
            ),
            const EditorialDivider(),

            // -----------------------------------------------------------------
            // SECCIÓN 2: NOTIFICACIONES Y SEGUNDO PLANO
            // -----------------------------------------------------------------
            const _SectionHeader(title: 'NOTIFICACIONES Y SEGUNDO PLANO'),
            _SettingsSwitchRow(
              title: 'Sincronización en segundo plano',
              subtitle:
                  'Actualizar noticias periódicamente (~60 min) con Android WorkManager aunque NexusBO no esté abierta.',
              value: settings.backgroundSyncEnabled,
              onChanged: (val) => _handleBackgroundSyncToggle(context, ref, val),
            ),
            const EditorialDivider(
              padding: EdgeInsets.symmetric(horizontal: 20),
            ),
            _SettingsSwitchRow(
              title: 'Notificaciones de noticias',
              subtitle:
                  'Recibir avisos de nuevas noticias publicadas por los medios monitoreados en el canal nexusbo_news.',
              value: settings.notificationsEnabled,
              onChanged: (val) => _handleNotificationsToggle(context, ref, val),
            ),
            const EditorialDivider(
              padding: EdgeInsets.symmetric(horizontal: 20),
            ),
            _SettingsSwitchRow(
              title: 'Reportes horarios automáticos',
              subtitle:
                  'Avisar cuando se cumpla una nueva hora con el resumen de noticias en el canal nexusbo_reports.',
              value: settings.hourlyReportsEnabled,
              onChanged: (val) {
                ref
                    .read(settingsProvider.notifier)
                    .setHourlyReportsEnabled(val);
              },
            ),
            if (!settings.backgroundSyncEnabled && settings.hourlyReportsEnabled) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Aviso: La sincronización en segundo plano está desactivada. NexusBO no podrá generar notificaciones horarias automáticas a menos que actives el interruptor superior.',
                          style: textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const EditorialDivider(),

            // -----------------------------------------------------------------
            // SECCIÓN 3: ACTUALIZACIÓN DE NOTICIAS
            // -----------------------------------------------------------------
            const _SectionHeader(title: 'ACTUALIZACIÓN DE NOTICIAS'),
            _SettingsSwitchRow(
              title: 'Actualizar al abrir la aplicación',
              subtitle:
                  'Sincroniza los medios automáticamente al iniciar NexusBO.',
              value: settings.autoRefreshOnOpen,
              onChanged: (val) {
                ref.read(settingsProvider.notifier).setAutoRefreshOnOpen(val);
              },
            ),
            const EditorialDivider(
              padding: EdgeInsets.symmetric(horizontal: 20),
            ),
            const _SettingsInfoRow(
              title: 'Plataforma editorial activa',
              subtitle: 'Red boliviana de noticias multi-medio',
              trailingText: 'Offline-First',
            ),
            const EditorialDivider(),

            // -----------------------------------------------------------------
            // SECCIÓN 4: CACHÉ Y ALMACENAMIENTO LOCAL
            // -----------------------------------------------------------------
            const _SectionHeader(title: 'CACHÉ Y ALMACENAMIENTO'),
            _SettingsInfoRow(
              title: 'Artículos almacenados offline',
              subtitle: 'Conserva tus noticias en favoritos sin conexión.',
              trailingText: '$cachedCount en SQLite',
            ),
            const EditorialDivider(
              padding: EdgeInsets.symmetric(horizontal: 20),
            ),
            InkWell(
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('¿Limpiar caché de noticias?'),
                    content: const Text(
                      'Se eliminarán las noticias almacenadas temporalmente y las imágenes en caché. Tus favoritos no se eliminarán.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.error,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ),
                );

                if (confirmed != true) return;

                final removed = await ref
                    .read(newsFeedProvider.notifier)
                    .clearLocalCache(keepFavorites: true);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        'Caché limpiada ($removed noticias temporales eliminadas). Tus favoritos fueron preservados.',
                      ),
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Limpiar caché de noticias',
                            style: textTheme.titleMedium?.copyWith(
                              color: colors.error,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Elimina noticias temporales manteniendo tus favoritos.',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: colors.error,
                    ),
                  ],
                ),
              ),
            ),
            const EditorialDivider(),

            // -----------------------------------------------------------------
            // SECCIÓN 5: HERRAMIENTAS DE DESARROLLO (SOLO EN DEBUG)
            // -----------------------------------------------------------------
            if (kDebugMode) ...[
              const _SectionHeader(title: 'DESARROLLADOR (SOLO DEBUG)'),
              _SettingsActionRow(
                title: 'Ejecutar sincronización background ahora',
                subtitle:
                    'Ejecuta la misma lógica del worker (sync -> detectar novedades -> notificar -> pruning).',
                icon: settings.isRunningDebugSync
                    ? Icons.hourglass_top_rounded
                    : Icons.sync_rounded,
                isLoading: settings.isRunningDebugSync,
                onTap: settings.isRunningDebugSync
                    ? null
                    : () => _handleDebugBackgroundSync(context, ref),
              ),
              const EditorialDivider(
                padding: EdgeInsets.symmetric(horizontal: 20),
              ),
              _SettingsActionRow(
                title: 'Enviar notificación de prueba',
                subtitle:
                    'Verifica canal nexusbo_news, permiso, visualización y navegación al tocar sin alterar SQLite.',
                icon: Icons.notifications_active_outlined,
                onTap: () => _handleDebugTestNotification(context, ref),
              ),
              const EditorialDivider(
                padding: EdgeInsets.symmetric(horizontal: 20),
              ),
              _SettingsActionRow(
                title: 'Simular reporte horario listo',
                subtitle:
                    'Dispara inmediatamente la notificación del canal nexusbo_reports con la última hora completa real en hora de Bolivia.',
                icon: Icons.schedule_send_outlined,
                onTap: () => _handleSimulateHourlyReport(context, ref),
              ),
              const EditorialDivider(
                padding: EdgeInsets.symmetric(horizontal: 20),
              ),
              _SettingsActionRow(
                title: 'Procesar recordatorio horario ahora',
                subtitle:
                    'Ejecuta la evaluación horaria respetando la ventana real de reporte con anti-flood.',
                icon: Icons.alarm_on_outlined,
                onTap: () => _handleProcessHourlyReportNow(context, ref),
              ),
              const EditorialDivider(),
            ],

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Text(
                'NexusBO v1.0.0 · Edición Android',
                style: textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return Container(
      width: double.infinity,
      color: colors.surfaceSecondary.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        title,
        style: textTheme.labelMedium?.copyWith(
          color: colors.primary,
        ),
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(subtitle, style: textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.title,
    required this.subtitle,
    required this.trailingText,
  });

  final String title;
  final String subtitle;
  final String trailingText;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              trailingText,
              style: textTheme.labelSmall?.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(subtitle, style: textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            else
              Icon(
                icon,
                size: 20,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({
    required this.selectedMode,
    required this.onChanged,
  });

  final ThemeMode selectedMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    const options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, 'Sistema', Icons.brightness_auto_outlined),
      (ThemeMode.light, 'Claro', Icons.light_mode_outlined),
      (ThemeMode.dark, 'Oscuro', Icons.dark_mode_outlined),
    ];

    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _buildOption(
              context: context,
              colors: colors,
              textTheme: textTheme,
              mode: options[i].$1,
              label: options[i].$2,
              icon: options[i].$3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required NexusColors colors,
    required TextTheme textTheme,
    required ThemeMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = mode == selectedMode;

    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => onChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryContainer : colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: textTheme.titleSmall?.copyWith(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
