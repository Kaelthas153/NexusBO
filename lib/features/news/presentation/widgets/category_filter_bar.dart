import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';

/// Barra horizontal de secciones editoriales con indicador inferior sobrio,
/// evitando el uso de chips redondeados genéricos.
class CategoryFilterBar extends StatelessWidget {
  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selectedCategory;

          return InkWell(
            onTap: () => onCategorySelected(category),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? colors.primary : Colors.transparent,
                    width: 2.2,
                  ),
                ),
              ),
              child: Text(
                category,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

