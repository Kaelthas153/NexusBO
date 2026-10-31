import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/core/utils/category_mapper.dart';

/// Etiqueta tipográfica sobria para mostrar la sección editorial
/// (ej. POLÍTICA, ECONOMÍA, SOCIEDAD) sin usar chips redondeados pesados.
class CategoryTag extends StatelessWidget {
  const CategoryTag({
    super.key,
    required this.label,
    this.isHighlighted = false,
  });

  final String label;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    final displayText = CategoryMapper.toDisplay(label).toUpperCase();

    if (isHighlighted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          displayText,
          style: textTheme.labelMedium?.copyWith(
            color: colors.primary,
            fontSize: 10.5,
          ),
        ),
      );
    }

    return Text(
      displayText,
      style: textTheme.labelMedium,
    );
  }
}

