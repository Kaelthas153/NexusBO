import 'package:flutter/material.dart';

/// Elemento decorativo discreto que se visualiza en la portada (Home) una vez
/// desbloqueado el secreto.
///
/// Es estrictamente pasivo y no interactivo (envuelto en [IgnorePointer]),
/// garantizando que no intercepte toques, scroll ni reserve espacio en el layout.
class UnlockedBouquetBadge extends StatelessWidget {
  const UnlockedBouquetBadge({
    super.key,
    this.height = 48.0,
  });

  /// Altura en dp del detalle decorativo (entre 40 y 56 dp).
  final double height;

  static const String assetPath =
      'assets/images/bouquet_mini_transparent.png';

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Image.asset(
        assetPath,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

