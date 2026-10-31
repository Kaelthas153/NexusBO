import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/features/news/presentation/providers/news_providers.dart';

/// Barra horizontal de filtrado editorial por fuente de noticias.
///
/// Presenta botones/chips sutiles que permiten alternar entre medios
/// (e.g. "Todas", "ABI", "DTV", "El Deber") sin ruido visual de dashboard
/// y con soporte automático para futuras fuentes mediante [SourceFilterOption].
class SourceFilterBar extends StatelessWidget {
  const SourceFilterBar({
    super.key,
    required this.options,
    required this.selectedSourceId,
    required this.onSourceSelected,
  });

  final List<SourceFilterOption> options;
  final String? selectedSourceId;
  final ValueChanged<String?> onSourceSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          // Si option.sourceId == null, está seleccionado si selectedSourceId == null
          final isSelected = option.isAll
              ? selectedSourceId == null
              : selectedSourceId == option.sourceId;

          return InkWell(
            onTap: () => onSourceSelected(option.sourceId),
            borderRadius: BorderRadius.circular(4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.12)
                    : colors.surfaceSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? colors.primary : colors.border,
                  width: isSelected ? 1.2 : 0.8,
                ),
              ),
              child: Text(
                option.displayName,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? colors.primary : colors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

