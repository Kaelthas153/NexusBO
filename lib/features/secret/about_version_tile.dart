import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexusbo/app/theme/app_colors.dart';
import 'package:nexusbo/features/secret/bouquet_reveal_overlay.dart';
import 'package:nexusbo/features/secret/secret_tap_controller.dart';
import 'package:nexusbo/features/settings/presentation/providers/settings_provider.dart';

/// Mensaje informativo presentado en la notificación tipo toast en el primer toque.
const String kSecretFirstTapHint =
    'Parece que hay algo especial escondido por aquí ...';

/// Notificación flotante informativa no bloqueante para los pasos previos al desbloqueo.
///
/// Se posiciona en la parte superior/media de la pantalla, completamente separada
/// del bloque de versión, y envuelta en [IgnorePointer] para permitir pulsaciones
/// consecutivas instantáneas sin interferir con taps ni scroll.
class SecretProgressNotice {
  SecretProgressNotice._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Muestra el aviso informativo en la parte superior de la pantalla.
  static void show(BuildContext context, String message) {
    dismiss();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (ctx) => IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding:
                  const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0),
              child: _NoticePill(message: message),
            ),
          ),
        ),
      ),
    );

    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(const Duration(milliseconds: 2000), () {
      dismiss();
    });
  }

  /// Descarta el aviso activo si existe.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _NoticePill extends StatelessWidget {
  const _NoticePill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, -6 * (1 - opacity)),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2420).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 14.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget interactivo para la sección "Acerca de NexusBO" que responde a la
/// secuencia secreta de 3 pulsaciones consecutivas sobre el texto de versión.
class AboutVersionTile extends ConsumerStatefulWidget {
  const AboutVersionTile({
    super.key,
    this.tapController,
    this.onUnlocked,
  });

  final SecretTapController? tapController;
  final VoidCallback? onUnlocked;

  @override
  ConsumerState<AboutVersionTile> createState() => _AboutVersionTileState();
}

class _AboutVersionTileState extends ConsumerState<AboutVersionTile> {
  late final SecretTapController _controller;

  @override
  void initState() {
    super.initState();
    final isAlreadyUnlocked = ref.read(easterEggUnlockedProvider);
    _controller = widget.tapController ??
        SecretTapController(isUnlocked: isAlreadyUnlocked);
    if (isAlreadyUnlocked) {
      _controller.isUnlocked = true;
    }
  }

  @override
  void dispose() {
    SecretProgressNotice.dismiss();
    super.dispose();
  }

  void _handleTap() {
    // Si ya fue desbloqueado previamente, ignorar taps para no volver a ejecutar la animación
    if (_controller.isUnlocked || ref.read(easterEggUnlockedProvider)) {
      return;
    }

    final outcome = _controller.registerTap();

    switch (outcome) {
      case SecretTapOutcome.firstTapHint:
        SecretProgressNotice.show(
          context,
          kSecretFirstTapHint,
        );
        break;
      case SecretTapOutcome.idle:
        // Segundo toque: no mostrar mensajes adicionales
        break;
      case SecretTapOutcome.unlocked:
        SecretProgressNotice.dismiss();
        HapticFeedback.mediumImpact();
        unawaited(ref.read(settingsProvider.notifier).unlockEasterEgg());
        BouquetRevealOverlay.show(context);
        widget.onUnlocked?.call();
        break;
      case SecretTapOutcome.alreadyUnlocked:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nexusColors;
    final textTheme = context.textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14.0),
              child: Image.asset(
                'assets/images/nexusbo_logo.png',
                width: 52,
                height: 52,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'NexusBO',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'NexusBO v1.0.0 - Edición Android',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
