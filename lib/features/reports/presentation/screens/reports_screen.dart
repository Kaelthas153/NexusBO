import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';
import 'package:nexusbo/features/reports/domain/models/monitoring_report.dart';
import 'package:nexusbo/features/reports/domain/services/monitoring_report_formatter.dart';
import 'package:nexusbo/features/reports/presentation/providers/reports_provider.dart';

/// Pantalla principal de Monitoreo y Reportes por rango horario de NexusBO.
///
/// Permite seleccionar fecha, ventana horaria y medios para generar reportes
/// consolidados desde SQLite preparados para copiar y compartir directamente en WhatsApp.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    super.key,
    this.initialStartUtc,
    this.initialEndUtc,
  });

  final DateTime? initialStartUtc;
  final DateTime? initialEndUtc;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialStartUtc != null && widget.initialEndUtc != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(reportsProvider.notifier).setWindowFromNotification(
              startUtc: widget.initialStartUtc!,
              endUtc: widget.initialEndUtc!,
            );
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStartUtc != null &&
        widget.initialEndUtc != null &&
        (widget.initialStartUtc != oldWidget.initialStartUtc ||
            widget.initialEndUtc != oldWidget.initialEndUtc)) {
      ref.read(reportsProvider.notifier).setWindowFromNotification(
            startUtc: widget.initialStartUtc!,
            endUtc: widget.initialEndUtc!,
          );
    }
  }

  Future<void> _pickDate(DateTime currentDate) async {
    final now = BoliviaDateFormatter.nowInBolivia();
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 1)),
      locale: const Locale('es', 'BO'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.darkPrimary,
              onPrimary: AppColors.darkBackground,
              surface: AppColors.darkSurface,
              onSurface: AppColors.darkTextPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(reportsProvider.notifier).setDate(picked);
    }
  }

  Future<void> _pickTime({
    required bool isStartTime,
    required TimeOfDay currentTime,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.darkPrimary,
              onPrimary: AppColors.darkBackground,
              surface: AppColors.darkSurface,
              onSurface: AppColors.darkTextPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final state = ref.read(reportsProvider);
      if (isStartTime) {
        ref.read(reportsProvider.notifier).setTimeRange(picked, state.endTime);
      } else {
        ref.read(reportsProvider.notifier).setTimeRange(state.startTime, picked);
      }
    }
  }

  void _copyReportToClipboard(MonitoringReport report) {
    final reportText = MonitoringReportFormatter.formatWhatsApp(report);
    Clipboard.setData(ClipboardData(text: reportText));

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Reporte copiado al portapapeles.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportsProvider);
    final registry = ref.watch(newsSourceRegistryProvider);
    final allSources = registry.getEnabledSources();

    final dateFormatted = BoliviaDateFormatter.formatDayMonthYear(state.selectedDate);
    final startTimeStr = BoliviaDateFormatter.format12Hour(
      DateTime(2026, 1, 1, state.startTime.hour, state.startTime.minute),
    );
    final endTimeStr = BoliviaDateFormatter.format12Hour(
      DateTime(2026, 1, 1, state.endTime.hour, state.endTime.minute),
    );

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reportes de Monitoreo',
              style: TextStyle(
                fontFamily: 'serif',
                fontWeight: FontWeight.bold,
                fontSize: 19,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Despacho horario consolidado para WhatsApp',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.darkTextSecondary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: AppColors.darkBorder,
            height: 1,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // -------------------------------------------------------------------
          // TARJETA DE CONTROLES EDITORIALES
          // -------------------------------------------------------------------
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Accesos rápidos
                Row(
                  children: [
                    _buildQuickChip(
                      label: 'Última hora',
                      isSelected: state.activeQuickOption == QuickReportFilter.lastHour,
                      onTap: () => ref
                          .read(reportsProvider.notifier)
                          .setQuickOption(QuickReportFilter.lastHour),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickChip(
                      label: 'Hoy',
                      isSelected: state.activeQuickOption == QuickReportFilter.today,
                      onTap: () => ref
                          .read(reportsProvider.notifier)
                          .setQuickOption(QuickReportFilter.today),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickChip(
                      label: 'Personalizado',
                      isSelected: state.activeQuickOption == QuickReportFilter.custom,
                      onTap: () => ref
                          .read(reportsProvider.notifier)
                          .setQuickOption(QuickReportFilter.custom),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Selector de Fecha y Rango Horario
                Row(
                  children: [
                    // Botón Fecha
                    Expanded(
                      flex: 4,
                      child: InkWell(
                        onTap: () => _pickDate(state.selectedDate),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurfaceSecondary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: AppColors.darkPrimary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  dateFormatted,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.darkTextPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Botón Hora Inicio
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () => _pickTime(
                          isStartTime: true,
                          currentTime: state.startTime,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurfaceSecondary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: Center(
                            child: Text(
                              startTimeStr,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkTextPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('–', style: TextStyle(color: AppColors.darkTextSecondary)),
                    ),

                    // Botón Hora Fin
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () => _pickTime(
                          isStartTime: false,
                          currentTime: state.endTime,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurfaceSecondary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: Center(
                            child: Text(
                              endTimeStr,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkTextPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Selector de Fuentes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'FUENTES DE NOTICIAS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => ref.read(reportsProvider.notifier).selectAllSources(),
                          child: const Text(
                            'Todas',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.darkPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => ref.read(reportsProvider.notifier).clearAllSources(),
                          child: const Text(
                            'Limpiar',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.darkTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Chips de selección múltiple de fuentes
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: allSources.map((source) {
                    final isChecked =
                        state.selectedSourceIds.contains(source.id.toLowerCase());
                    return FilterChip(
                      label: Text(source.name),
                      selected: isChecked,
                      onSelected: (_) =>
                          ref.read(reportsProvider.notifier).toggleSource(source.id),
                      backgroundColor: AppColors.darkSurfaceSecondary,
                      selectedColor: AppColors.darkPrimaryContainer,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: isChecked
                            ? AppColors.darkPrimary
                            : AppColors.darkTextSecondary,
                        fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(
                          color: isChecked
                              ? AppColors.darkPrimary
                              : AppColors.darkBorder,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Botón Principal de Actualización y Generación
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: state.isLoading || state.isSyncing
                        ? null
                        : () => ref
                            .read(reportsProvider.notifier)
                            .generateReport(forceSync: true),
                    icon: state.isSyncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.darkBackground,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(
                      state.isSyncing
                          ? 'SINCRONIZANDO FUENTES...'
                          : (state.isLoading ? 'GENERANDO REPORTE...' : 'ACTUALIZAR Y GENERAR'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.darkPrimary,
                      foregroundColor: AppColors.darkBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // -------------------------------------------------------------------
          // BANNER DE ESTADO / ADVERTENCIA DE SINCRONIZACIÓN
          // -------------------------------------------------------------------
          if (state.syncStatusMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceSecondary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.darkPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.syncStatusMessage!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // -------------------------------------------------------------------
          // VISTA PREVIA DEL REPORTE
          // -------------------------------------------------------------------
          if (state.report != null) ...[
            _buildReportPreviewCard(state.report!),
          ] else if (state.isLoading) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.darkPrimaryContainer
              : AppColors.darkSurfaceSecondary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.darkPrimary : AppColors.darkBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? AppColors.darkPrimary : AppColors.darkTextSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildReportPreviewCard(MonitoringReport report) {
    final headerTitle = MonitoringReportFormatter.buildHeader(report.startUtc, report.endUtc);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de cabecera con botón de copia
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${report.totalArticles} noticias • ${report.activeSourcesCount} medios con actividad',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.darkTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: report.isEmpty ? null : () => _copyReportToClipboard(report),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text(
                    'COPIAR',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.darkPrimary,
                    foregroundColor: AppColors.darkBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.darkBorder),

          // Contenido o Estado Vacío
          if (report.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.newspaper_outlined,
                      size: 32,
                      color: AppColors.darkTextSecondary,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No se encontraron noticias publicadas en este rango.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final section in report.sections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: Text(
                        section.sourceName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    for (final article in section.articles) ...[
                      Dismissible(
                        key: ValueKey('report_item_${article.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppColors.darkError.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.delete_outline,
                                color: AppColors.darkError,
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Quitar del reporte',
                                style: TextStyle(
                                  color: AppColors.darkError,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (_) {
                          ref
                              .read(reportsProvider.notifier)
                              .excludeArticle(article.id);
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Noticia excluida del reporte.',
                                ),
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                                action: SnackBarAction(
                                  label: 'DESHACER',
                                  textColor: AppColors.darkPrimary,
                                  onPressed: () {
                                    ref
                                        .read(reportsProvider.notifier)
                                        .restoreExcludedArticle(article.id);
                                  },
                                ),
                              ),
                            );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ${article.title}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                MonitoringReportFormatter.extractCleanSummary(article),
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: AppColors.darkTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                article.url,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.darkPrimary.withValues(alpha: 0.85),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: 16, color: AppColors.darkBorder),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

