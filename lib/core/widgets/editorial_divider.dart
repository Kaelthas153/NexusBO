import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';

/// Separador horizontal sutil de corte editorial.
class EditorialDivider extends StatelessWidget {
  const EditorialDivider({
    super.key,
    this.padding = EdgeInsets.zero,
    this.emphasized = false,
  });

  final EdgeInsetsGeometry padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    return Padding(
      padding: padding,
      child: Container(
        height: emphasized ? 1.5 : 1.0,
        width: double.infinity,
        color: emphasized ? colors.textPrimary : colors.border,
      ),
    );
  }
}

