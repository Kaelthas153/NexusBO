import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexusbo/features/secret/bouquet_audio_service.dart';

/// Overlay que presenta la animación nativa de revelado del bouquet en NexusBO.
///
/// Reproduce la secuencia de revelado de 5 regiones en ~2.2 segundos con pop
/// final y chime sincronizado, sin incluir ningún texto ni interrumpir la navegación.
class BouquetRevealOverlay {
  BouquetRevealOverlay._();

  static OverlayEntry? _currentEntry;

  /// Muestra el overlay encima de la pantalla activa.
  static void show(
    BuildContext context, {
    BouquetAudioService? audioService,
    VoidCallback? onComplete,
  }) {
    // Si ya existe un overlay activo, descartarlo limpiamente primero
    dismiss();

    final overlayState = Overlay.of(context, rootOverlay: true);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _BouquetRevealWidget(
        audioService: audioService ?? AppBouquetAudioService(),
        onFinished: () {
          dismiss();
          onComplete?.call();
        },
      ),
    );

    _currentEntry = entry;
    overlayState.insert(entry);
  }

  /// Cierra y libera el overlay actual si se encuentra activo.
  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _BouquetRevealWidget extends StatefulWidget {
  const _BouquetRevealWidget({
    required this.audioService,
    required this.onFinished,
  });

  final BouquetAudioService audioService;
  final VoidCallback onFinished;

  @override
  State<_BouquetRevealWidget> createState() => _BouquetRevealWidgetState();
}

class _BouquetRevealWidgetState extends State<_BouquetRevealWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ui.Image? _decodedImage;
  bool _audioTriggered = false;
  bool _isExiting = false;

  static const String assetImagePath =
      'assets/images/bouquet_reveal_transparent.png';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _controller.addListener(_handleAnimationTick);
    _controller.addStatusListener(_handleAnimationStatus);

    _loadImageAndStart();
  }

  Future<void> _loadImageAndStart() async {
    // Precargar audio en paralelo
    unawaited(widget.audioService.preload());

    try {
      final data = await rootBundle.load(assetImagePath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();

      if (!mounted) return;
      setState(() {
        _decodedImage = frame.image;
      });
      _controller.forward();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NexusBO: Fallback al cargar imagen de bouquet: $e');
      }
      if (!mounted) return;
      _controller.forward();
    }
  }

  void _handleAnimationTick() {
    // Sincronizar el chime de audio en t = 1.55s (1550ms de 2200ms -> t >= 0.7045)
    const audioTriggerTime = 1.55 / 2.20;
    if (!_audioTriggered && _controller.value >= audioTriggerTime) {
      _audioTriggered = true;
      unawaited(widget.audioService.playChime());
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _isExiting = true;
      });
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          widget.onFinished();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleAnimationTick);
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    widget.audioService.dispose();
    super.dispose();
  }

  double _calculatePopScale(double progress) {
    const popStart = 1.55 / 2.20;
    const popEnd = 1.90 / 2.20;

    if (progress < popStart || progress > popEnd) {
      return 1.0;
    }

    final t = (progress - popStart) / (popEnd - popStart);
    if (t < 0.5) {
      final p = t / 0.5;
      return 0.97 + (1.025 - 0.97) * Curves.easeOut.transform(p);
    } else {
      final p = (t - 0.5) / 0.5;
      return 1.025 - (1.025 - 1.0) * Curves.easeInOut.transform(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bouquetWidth = (size.width * 0.72).clamp(240.0, 320.0);
    final bouquetHeight = bouquetWidth * (516.0 / 381.0);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      builder: (context, entranceOpacity, child) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _isExiting ? 0.0 : entranceOpacity,
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Overlay detrás: Pantalla actual ligeramente atenuada
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),

            // Superficie clara como lienzo limpio detrás de la ilustración
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 28.0,
                vertical: 32.0,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8F9),
                borderRadius: BorderRadius.circular(32.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 28.0,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final scale = _calculatePopScale(_controller.value);

                  return Transform.scale(
                    scale: scale,
                    child: SizedBox(
                      width: bouquetWidth,
                      height: bouquetHeight,
                      child: CustomPaint(
                        painter: BouquetRevealPainter(
                          image: _decodedImage,
                          progress: _controller.value,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter encargado de aplicar la máscara de 5 regiones sobre la imagen del bouquet.
class BouquetRevealPainter extends CustomPainter {
  BouquetRevealPainter({
    required this.image,
    required this.progress,
  });

  final ui.Image? image;
  final double progress;

  static const double baseWidth = 381.0;
  static const double baseHeight = 516.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null || progress <= 0.0) return;

    // Regla principal: Antes de que comience el reveal (t < 0.20s),
    // el lienzo debe estar TOTALMENTE VACÍO (cero imagen tenue o fantasma).
    const startDelay = 0.20 / 2.20;
    if (progress < startDelay) return;

    final rect = Offset.zero & size;
    final scaleX = size.width / baseWidth;
    final scaleY = size.height / baseHeight;

    // FASE B: Reveal completado (a partir de ~1.45s).
    // Las regiones ya formaron la imagen completa; renderizar UNA sola copia completa.
    const revealComplete = 1.45 / 2.20;
    if (progress >= revealComplete) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: image!,
        fit: BoxFit.contain,
      );
      return;
    }

    // FASE A: Únicamente las regiones reveladas por la máscara progresiva.
    // Creamos una capa aislada para la máscara acumulativa.
    canvas.saveLayer(rect, Paint());

    // 1. Dibujar la máscara blanca acumulativa (desenfoque gaussiano suave)
    final maskFilter = MaskFilter.blur(BlurStyle.normal, 14.0 * scaleX);

    // Región A: Centro floral superior (0.20s - 0.60s)
    _drawMaskRegion(
      canvas: canvas,
      center: Offset(190.0 * scaleX, 170.0 * scaleY),
      rx: 65.0 * scaleX,
      ry: 90.0 * scaleY,
      startTime: 0.20 / 2.20,
      endTime: 0.60 / 2.20,
      maskFilter: maskFilter,
    );

    // Región B: Zona izquierda (0.45s - 0.85s)
    _drawMaskRegion(
      canvas: canvas,
      center: Offset(135.0 * scaleX, 180.0 * scaleY),
      rx: 80.0 * scaleX,
      ry: 105.0 * scaleY,
      startTime: 0.45 / 2.20,
      endTime: 0.85 / 2.20,
      maskFilter: maskFilter,
    );

    // Región C: Zona derecha (0.70s - 1.10s)
    _drawMaskRegion(
      canvas: canvas,
      center: Offset(245.0 * scaleX, 180.0 * scaleY),
      rx: 80.0 * scaleX,
      ry: 105.0 * scaleY,
      startTime: 0.70 / 2.20,
      endTime: 1.10 / 2.20,
      maskFilter: maskFilter,
    );

    // Región D: Envoltorio kraft inferior y lazo (0.95s - 1.35s)
    _drawMaskRegion(
      canvas: canvas,
      center: Offset(190.0 * scaleX, 350.0 * scaleY),
      rx: 95.0 * scaleX,
      ry: 145.0 * scaleY,
      startTime: 0.95 / 2.20,
      endTime: 1.35 / 2.20,
      maskFilter: maskFilter,
    );

    // Región E: Silueta completa (1.20s - 1.45s)
    const eStart = 1.20 / 2.20;
    const eEnd = revealComplete;
    if (progress >= eStart) {
      final t = ((progress - eStart) / (eEnd - eStart)).clamp(0.0, 1.0);
      final alpha = (t * 255).round();
      if (alpha > 0) {
        final fullPaint = Paint()
          ..color = Color.fromARGB(alpha, 255, 255, 255);
        canvas.drawRect(rect, fullPaint);
      }
    }

    // 2. Componer la imagen con BlendMode.srcIn:
    // La imagen se muestra ÚNICAMENTE donde la máscara blanca acumulada fue dibujada.
    // Fuera de la máscara, la opacidad es estrictamente 0 (cero imagen fantasma).
    paintImage(
      canvas: canvas,
      rect: rect,
      image: image!,
      fit: BoxFit.contain,
      blendMode: BlendMode.srcIn,
    );

    canvas.restore();
  }

  void _drawMaskRegion({
    required Canvas canvas,
    required Offset center,
    required double rx,
    required double ry,
    required double startTime,
    required double endTime,
    required MaskFilter maskFilter,
  }) {
    if (progress < startTime) return;

    final t = ((progress - startTime) / (endTime - startTime)).clamp(0.0, 1.0);
    final eased = Curves.easeOut.transform(t);
    final scale = 0.85 + (0.15 * eased);
    final alpha = (eased * 255).round();

    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..maskFilter = maskFilter;

    final ovalRect = Rect.fromCenter(
      center: center,
      width: rx * 2 * scale,
      height: ry * 2 * scale,
    );
    canvas.drawOval(ovalRect, paint);
  }

  @override
  bool shouldRepaint(covariant BouquetRevealPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.image != image;
  }
}

