import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';

/// Vista de estado vacío con estética editorial limpia para Buscar y Favoritos.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 22,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            eyebrow.toUpperCase(),
            style: textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

