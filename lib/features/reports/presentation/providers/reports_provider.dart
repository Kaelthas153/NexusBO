import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/core/utils/date_formatter.dart';
import 'package:nexusbo/features/news/data/models/article_model.dart';
import 'package:nexusbo/features/news/domain/repositories/news_repository.dart';
import 'package:nexusbo/features/news/domain/sources/news_source_registry.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';
import 'package:nexusbo/features/reports/domain/models/monitoring_report.dart';
import 'package:nexusbo/features/reports/domain/services/monitoring_report_service.dart';
import 'package:nexusbo/features/settings/presentation/providers/settings_provider.dart';
import 'package:nexusbo/services/preferences/app_preferences_service.dart';

enum QuickReportFilter {
  lastHour,
  today,
  custom,
}

@immutable
class ReportsState {
  const ReportsState({
    required this.selectedDate,
    required this.startTime,
    required this.endTime,
    required this.isModeAllSources,
    required this.selectedSourceIds,
    required this.activeQuickOption,
    this.excludedArticleIds = const <String>{},
    this.isLoading = false,
    this.isSyncing = false,
    this.report,
    this.syncStatusMessage,
    this.errorMessage,
  });

  final DateTime selectedDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool isModeAllSources;
  final Set<String> selectedSourceIds;
  final QuickReportFilter activeQuickOption;
  final Set<String> excludedArticleIds;
  final bool isLoading;
  final bool isSyncing;
  final MonitoringReport? report;
  final String? syncStatusMessage;
  final String? errorMessage;

  ReportsState copyWith({
    DateTime? selectedDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool? isModeAllSources,
    Set<String>? selectedSourceIds,
    QuickReportFilter? activeQuickOption,
    Set<String>? excludedArticleIds,
    bool? isLoading,
    bool? isSyncing,
    MonitoringReport? report,
    String? syncStatusMessage,
    bool clearSyncStatusMessage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ReportsState(
      selectedDate: selectedDate ?? this.selectedDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isModeAllSources: isModeAllSources ?? this.isModeAllSources,
      selectedSourceIds: selectedSourceIds ?? this.selectedSourceIds,
      activeQuickOption: activeQuickOption ?? this.activeQuickOption,
      excludedArticleIds: excludedArticleIds ?? this.excludedArticleIds,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      report: report ?? this.report,
      syncStatusMessage: clearSyncStatusMessage
          ? null
          : (syncStatusMessage ?? this.syncStatusMessage),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ReportsNotifier extends Notifier<ReportsState> {
  @override
  ReportsState build() {
    Future<void>.microtask(_loadPreferencesAndInitialize);
    return _initialState();
  }

  NewsRepository get _repository => ref.read(newsRepositoryProvider);
  NewsSourceRegistry get _registry => ref.read(newsSourceRegistryProvider);
  AppPreferencesDataSource get _preferences => ref.read(appPreferencesProvider);

  static ReportsState _initialState() {
    final window =
        MonitoringReportService.calculateLastCompleteHourWindow();
    return ReportsState(
      selectedDate: DateTime(
        window.startBolivia.year,
        window.startBolivia.month,
        window.startBolivia.day,
      ),
      startTime: TimeOfDay(
        hour: window.startBolivia.hour,
        minute: window.startBolivia.minute,
      ),
      endTime: TimeOfDay(
        hour: window.endBolivia.hour,
        minute: window.endBolivia.minute,
      ),
      isModeAllSources: true,
      selectedSourceIds: const <String>{},
      activeQuickOption: QuickReportFilter.lastHour,
    );
  }

  Future<void> _loadPreferencesAndInitialize() async {
    final isAll = await _preferences.getReportSourcesModeAll();
    final savedIds = await _preferences.getReportSelectedSourceIds();
    final enabledSources = _registry.getEnabledSources();
    final allIds = enabledSources.map((s) => s.id.toLowerCase()).toSet();

    final Set<String> effectiveIds;
    if (isAll || savedIds.isEmpty) {
      effectiveIds = allIds;
    } else {
      effectiveIds = savedIds.map((s) => s.toLowerCase()).toSet();
    }

    state = state.copyWith(
      isModeAllSources: isAll,
      selectedSourceIds: effectiveIds,
    );

    await generateReport(forceSync: true);
  }

  /// Inicializa los filtros con un rango específico proveniente de una notificación.
  Future<void> setWindowFromNotification({
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final startBolivia = BoliviaDateFormatter.toBoliviaTime(startUtc);
    final endBolivia = BoliviaDateFormatter.toBoliviaTime(endUtc);

    state = state.copyWith(
      selectedDate: DateTime(
        startBolivia.year,
        startBolivia.month,
        startBolivia.day,
      ),
      startTime: TimeOfDay(
        hour: startBolivia.hour,
        minute: startBolivia.minute,
      ),
      endTime: TimeOfDay(
        hour: endBolivia.hour,
        minute: endBolivia.minute,
      ),
      activeQuickOption: QuickReportFilter.custom,
    );

    await generateReport(forceSync: false);
  }

  void setQuickOption(QuickReportFilter option) {
    if (option == QuickReportFilter.lastHour) {
      final window =
          MonitoringReportService.calculateLastCompleteHourWindow();
      state = state.copyWith(
        selectedDate: DateTime(
          window.startBolivia.year,
          window.startBolivia.month,
          window.startBolivia.day,
        ),
        startTime: TimeOfDay(
          hour: window.startBolivia.hour,
          minute: window.startBolivia.minute,
        ),
        endTime: TimeOfDay(
          hour: window.endBolivia.hour,
          minute: window.endBolivia.minute,
        ),
        activeQuickOption: QuickReportFilter.lastHour,
      );
    } else if (option == QuickReportFilter.today) {
      final nowBolivia = BoliviaDateFormatter.nowInBolivia();
      state = state.copyWith(
        selectedDate: DateTime(
          nowBolivia.year,
          nowBolivia.month,
          nowBolivia.day,
        ),
        startTime: const TimeOfDay(hour: 0, minute: 0),
        endTime: TimeOfDay(hour: nowBolivia.hour, minute: nowBolivia.minute),
        activeQuickOption: QuickReportFilter.today,
      );
    } else {
      state = state.copyWith(activeQuickOption: QuickReportFilter.custom);
    }
  }

  void setDate(DateTime date) {
    state = state.copyWith(
      selectedDate: DateTime(date.year, date.month, date.day),
      activeQuickOption: QuickReportFilter.custom,
    );
  }

  void setTimeRange(TimeOfDay start, TimeOfDay end) {
    state = state.copyWith(
      startTime: start,
      endTime: end,
      activeQuickOption: QuickReportFilter.custom,
    );
  }

  Future<void> toggleSource(String sourceId) async {
    final lower = sourceId.toLowerCase();
    final updated = Set<String>.from(state.selectedSourceIds);
    if (updated.contains(lower)) {
      updated.remove(lower);
    } else {
      updated.add(lower);
    }

    final enabled = _registry.getEnabledSources();
    final isAll = updated.length == enabled.length;

    state = state.copyWith(
      selectedSourceIds: updated,
      isModeAllSources: isAll,
    );

    await _preferences.setReportSourcesModeAll(isAll);
    await _preferences.setReportSelectedSourceIds(updated.toList());
  }

  Future<void> selectAllSources() async {
    final enabled = _registry.getEnabledSources();
    final allIds = enabled.map((s) => s.id.toLowerCase()).toSet();

    state = state.copyWith(
      selectedSourceIds: allIds,
      isModeAllSources: true,
    );

    await _preferences.setReportSourcesModeAll(true);
    await _preferences.setReportSelectedSourceIds(allIds.toList());
  }

  Future<void> clearAllSources() async {
    state = state.copyWith(
      selectedSourceIds: const <String>{},
      isModeAllSources: false,
    );

    await _preferences.setReportSourcesModeAll(false);
    await _preferences.setReportSelectedSourceIds(const <String>[]);
  }

  List<ArticleModel> _lastRetrievedArticles = const <ArticleModel>[];
  DateTime? _lastStartUtc;
  DateTime? _lastEndUtc;

  void _rebuildReportWithExclusions() {
    if (_lastStartUtc == null || _lastEndUtc == null) return;
    final orderedSources = _registry
        .getEnabledSources()
        .where((s) => state.selectedSourceIds.contains(s.id.toLowerCase()))
        .toList();

    final filteredArticles = _lastRetrievedArticles
        .where((a) => !state.excludedArticleIds.contains(a.id))
        .toList();

    final report = MonitoringReportService.buildReport(
      startUtc: _lastStartUtc!,
      endUtc: _lastEndUtc!,
      articles: filteredArticles,
      orderedSources: orderedSources,
      syncWarning: state.syncStatusMessage,
    );

    state = state.copyWith(report: report);
  }

  void excludeArticle(String articleId) {
    final updated = Set<String>.from(state.excludedArticleIds)..add(articleId);
    state = state.copyWith(excludedArticleIds: updated);
    _rebuildReportWithExclusions();
  }

  void restoreExcludedArticle(String articleId) {
    final updated = Set<String>.from(state.excludedArticleIds)..remove(articleId);
    state = state.copyWith(excludedArticleIds: updated);
    _rebuildReportWithExclusions();
  }

  /// Genera el reporte consultando SQLite, precedido por una sincronización de las fuentes
  /// seleccionadas si el rango solicitado corresponde a las últimas 24 horas.
  Future<void> generateReport({bool forceSync = true}) async {
    state = state.copyWith(
      isLoading: true,
      excludedArticleIds: const <String>{},
      clearErrorMessage: true,
      clearSyncStatusMessage: true,
    );

    try {
      // 1. Calcular instantes UTC exactos
      final startBolivia = DateTime(
        state.selectedDate.year,
        state.selectedDate.month,
        state.selectedDate.day,
        state.startTime.hour,
        state.startTime.minute,
      );

      DateTime endBolivia;
      if (state.endTime.hour < state.startTime.hour ||
          (state.endTime.hour == state.startTime.hour &&
              state.endTime.minute <= state.startTime.minute)) {
        // Cruce de medianoche al día siguiente
        endBolivia = DateTime(
          state.selectedDate.year,
          state.selectedDate.month,
          state.selectedDate.day + 1,
          state.endTime.hour,
          state.endTime.minute,
        );
      } else {
        endBolivia = DateTime(
          state.selectedDate.year,
          state.selectedDate.month,
          state.selectedDate.day,
          state.endTime.hour,
          state.endTime.minute,
        );
      }

      final startUtc = BoliviaDateFormatter.boliviaTimeToUtc(startBolivia);
      final endUtc = BoliviaDateFormatter.boliviaTimeToUtc(endBolivia);

      final isRecent = MonitoringReportService.isRecentRange(startUtc, endUtc);
      String? syncStatusMessage;

      // 2. Sincronizar fuentes seleccionadas si es un rango reciente
      if (isRecent && forceSync && state.selectedSourceIds.isNotEmpty) {
        state = state.copyWith(isSyncing: true);

        final targetSources = _registry
            .getEnabledSources()
            .where(
              (s) => state.selectedSourceIds.contains(s.id.toLowerCase()),
            )
            .toList();

        if (targetSources.isNotEmpty) {
          try {
            final syncResult =
                await _repository.syncSelectedSources(targetSources);
            if (syncResult.warning != null) {
              syncStatusMessage = syncResult.warning;
            }
          } catch (_) {
            syncStatusMessage =
                'No fue posible actualizar las fuentes. Mostrando información almacenada localmente.';
          }
        }
      }

      // 3. Consultar SQLite como Single Source of Truth
      final selectedList = state.selectedSourceIds.toList();
      final entityList = await _repository.getArticlesForReport(
        startUtc: startUtc,
        endUtc: endUtc,
        sourceIds: selectedList,
      );
      final articles =
          entityList.map((e) => ArticleModel.fromEntity(e)).toList();

      _lastRetrievedArticles = articles;
      _lastStartUtc = startUtc;
      _lastEndUtc = endUtc;

      // 4. Construir el reporte ordenado
      final orderedSources = _registry
          .getEnabledSources()
          .where((s) => state.selectedSourceIds.contains(s.id.toLowerCase()))
          .toList();

      final report = MonitoringReportService.buildReport(
        startUtc: startUtc,
        endUtc: endUtc,
        articles: articles,
        orderedSources: orderedSources,
        syncWarning: syncStatusMessage,
      );

      state = state.copyWith(
        isLoading: false,
        isSyncing: false,
        report: report,
        syncStatusMessage: syncStatusMessage,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSyncing: false,
        errorMessage: 'Error al generar el reporte: $e',
      );
    }
  }
}

final reportsProvider =
    NotifierProvider<ReportsNotifier, ReportsState>(ReportsNotifier.new);
