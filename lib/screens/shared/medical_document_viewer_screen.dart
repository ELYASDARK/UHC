import 'package:flutter/material.dart';

/// Fullscreen mobile image viewer for medical document images.
///
/// Android's in-app browser can choose a poor initial scale for direct Storage
/// image URLs. This viewer keeps the first view fitted to the screen while
/// still allowing manual zoom without document scrolling or panning.
class MedicalDocumentViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String title;

  const MedicalDocumentViewerScreen({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  @override
  State<MedicalDocumentViewerScreen> createState() =>
      _MedicalDocumentViewerScreenState();
}

class _MedicalDocumentViewerScreenState
    extends State<MedicalDocumentViewerScreen>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.5;

  final TransformationController _transform = TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final animation = _animation;
        if (animation != null) {
          _transform.value = animation.value;
        }
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transform.dispose();
    super.dispose();
  }

  double get _currentScale => _transform.value.getMaxScaleOnAxis();

  Matrix4 _centeredScale(double scale) {
    final safeScale = scale.clamp(1.0, 8.0).toDouble();
    return Matrix4.diagonal3Values(safeScale, safeScale, 1);
  }

  void _animateToScale(double scale) {
    _animationController.stop();
    _animation = Matrix4Tween(
      begin: _centeredScale(_currentScale),
      end: _centeredScale(scale),
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _animationController
      ..reset()
      ..forward();
  }

  void _keepDocumentCentered() {
    final scale = _currentScale;
    if (scale.isFinite && scale > 0) {
      final centered = _centeredScale(scale);
      if (_transform.value != centered) {
        _transform.value = centered;
      }
    }
  }

  void _handleDoubleTap() {
    if (_currentScale > 1.05) {
      _animateToScale(1);
      return;
    }

    _animateToScale(_doubleTapScale);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF4F7FA),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    color: Colors.white70,
                    tooltip: 'Reset zoom',
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    onPressed: () => _animateToScale(1),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: _handleDoubleTap,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      alignment: Alignment.center,
                      minScale: 1,
                      maxScale: 8,
                      panEnabled: false,
                      scaleEnabled: true,
                      boundaryMargin: EdgeInsets.zero,
                      onInteractionUpdate: (_) => _keepDocumentCentered(),
                      onInteractionEnd: (_) => _keepDocumentCentered(),
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: Center(
                          child: Image.network(
                            widget.imageUrl,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            loadingBuilder: (
                              context,
                              child,
                              loadingProgress,
                            ) {
                              if (loadingProgress == null) return child;
                              final expected =
                                  loadingProgress.expectedTotalBytes;
                              final loaded =
                                  loadingProgress.cumulativeBytesLoaded;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: expected == null
                                      ? null
                                      : loaded / expected,
                                  color: Colors.white,
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 48,
                                ),
                              );
                            },
                          ),
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
