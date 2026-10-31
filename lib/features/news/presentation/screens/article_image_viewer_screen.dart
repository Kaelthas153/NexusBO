import 'package:flutter/material.dart';
import 'package:nexusbo/app/theme/app_colors.dart';

/// Visor de imágenes en pantalla completa para artículos de NexusBO.
///
/// Implementado con capacidades nativas de Flutter (`PageView` +
/// `InteractiveViewer` + `TransformationController`):
/// - Pinch-to-zoom (hasta 4.0x).
/// - Desplazamiento (pan) cuando existe zoom activo.
/// - Doble toque (double tap) para acercar (2.5x) en el punto tocado o
///   restablecer a escala 1.0x.
/// - Navegación mediante swipe horizontal cuando el artículo tiene varias
///   imágenes.
class ArticleImageViewerScreen extends StatefulWidget {
  const ArticleImageViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    required this.articleTitle,
  });

  final List<String> imageUrls;
  final int initialIndex;
  final String articleTitle;

  @override
  State<ArticleImageViewerScreen> createState() =>
      _ArticleImageViewerScreenState();
}

class _ArticleImageViewerScreenState extends State<ArticleImageViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isCurrentPageZoomed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1,
    );
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1012),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1012),
        foregroundColor: AppColors.darkTextPrimary,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cerrar visor',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: total > 1
            ? Text(
                '${_currentIndex + 1} / $total',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkTextPrimary,
                  letterSpacing: 0.6,
                ),
              )
            : null,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: _isCurrentPageZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: total,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _isCurrentPageZoomed = false;
                  });
                },
                itemBuilder: (context, index) {
                  return _ZoomableImagePage(
                    imageUrl: widget.imageUrls[index],
                    onZoomStateChanged: (isZoomed) {
                      if (_isCurrentPageZoomed != isZoomed && mounted) {
                        setState(() {
                          _isCurrentPageZoomed = isZoomed;
                        });
                      }
                    },
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              decoration: const BoxDecoration(
                color: Color(0xFF0B1012),
                border: Border(
                  top: BorderSide(color: AppColors.darkBorder, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.articleTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.darkTextSecondary,
                      height: 1.35,
                    ),
                  ),
                  if (total > 1) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List<Widget>.generate(total, (index) {
                        final isSelected = index == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: isSelected ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.darkPrimary
                                : AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableImagePage extends StatefulWidget {
  const _ZoomableImagePage({
    required this.imageUrl,
    required this.onZoomStateChanged,
  });

  final String imageUrl;
  final ValueChanged<bool> onZoomStateChanged;

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  static const double _doubleTapZoomScale = 2.5;
  static const double _maxScale = 4.0;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    widget.onZoomStateChanged(currentScale > 1.02);
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _transformationController.value = Matrix4.identity();
      widget.onZoomStateChanged(false);
      return;
    }

    final position = _doubleTapDetails?.localPosition;
    if (position == null) {
      _transformationController.value = Matrix4.identity()
        ..scaleByDouble(
          _doubleTapZoomScale,
          _doubleTapZoomScale,
          1.0,
          1.0,
        );
      widget.onZoomStateChanged(true);
      return;
    }

    // Acercar centrando en el punto donde el usuario hizo doble toque
    final dx = -position.dx * (_doubleTapZoomScale - 1);
    final dy = -position.dy * (_doubleTapZoomScale - 1);
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(
        _doubleTapZoomScale,
        _doubleTapZoomScale,
        1.0,
        1.0,
      );
    widget.onZoomStateChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1.0,
        maxScale: _maxScale,
        panEnabled: true,
        scaleEnabled: true,
        child: Center(
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.darkPrimary,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 36,
                    color: AppColors.darkTextSecondary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No fue posible cargar la imagen en tamaño completo.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

