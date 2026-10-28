import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A fitted document image with focal zoom and bounds based on the image itself.
class MedicalDocumentViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String title;
  final Widget? captureContent;
  final Size? captureImageSize;

  const MedicalDocumentViewerScreen({
    super.key,
    required this.imageUrl,
    required this.title,
    this.captureContent,
    this.captureImageSize,
  });

  @override
  State<MedicalDocumentViewerScreen> createState() =>
      _MedicalDocumentViewerScreenState();
}

class _MedicalDocumentViewerScreenState
    extends State<MedicalDocumentViewerScreen>
    with SingleTickerProviderStateMixin {
  static const double _maxScale = 8;
  late final AnimationController _animationController;
  late NetworkImage _provider;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _imageSize;
  bool _failed = false;

  Size _viewport = Size.zero;
  Size _fitted = Size.zero;
  double _scale = 1;
  Offset _offset = Offset.zero;
  Offset _doubleTapPosition = Offset.zero;
  final Map<int, Offset> _pointers = {};
  Offset _pointerStartFocalPoint = Offset.zero;
  Offset _previousFocalPoint = Offset.zero;
  double _previousGestureScale = 1;
  int _pointerCount = 0;
  double _animationStartScale = 1;
  double _animationEndScale = 1;
  Offset _animationStartOffset = Offset.zero;
  Offset _animationEndOffset = Offset.zero;

  bool get _ready => widget.captureContent != null || _imageSize != null;

  @override
  void initState() {
    super.initState();
    _provider = NetworkImage(widget.imageUrl);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final t = Curves.easeOutCubic.transform(_animationController.value);
        setState(() {
          _scale = _animationStartScale +
              (_animationEndScale - _animationStartScale) * t;
          _offset = _boundOffset(
            Offset.lerp(_animationStartOffset, _animationEndOffset, t)!,
            _scale,
          );
        });
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant MedicalDocumentViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.captureContent != widget.captureContent ||
        oldWidget.captureImageSize != widget.captureImageSize) {
      _animationController.stop();
      _provider = NetworkImage(widget.imageUrl);
      _imageSize = null;
      _failed = false;
      _viewport = Size.zero;
      _resolveImage();
    }
  }

  void _resolveImage() {
    _detachImageListener();
    if (widget.captureContent != null) return;
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    _imageStream = stream;
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        final size =
            Size(info.image.width.toDouble(), info.image.height.toDouble());
        info.dispose();
        if (!mounted || _imageStream != stream) return;
        setState(() {
          _imageSize = size;
          _failed = false;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted || _imageStream != stream) return;
        setState(() {
          _imageSize = null;
          _failed = true;
        });
      },
    );
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _detachImageListener() {
    final listener = _imageListener;
    if (listener != null) _imageStream?.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
  }

  @override
  void dispose() {
    _detachImageListener();
    _animationController.dispose();
    super.dispose();
  }

  // On each axis, a smaller image stays centered. A larger image must cover
  // the viewport, so dragging can never expose avoidable empty space.
  Offset _boundOffset(Offset offset, double scale) {
    double bound(double value, double imageExtent, double viewportExtent) =>
        imageExtent <= viewportExtent
            ? (viewportExtent - imageExtent) / 2
            : value.clamp(viewportExtent - imageExtent, 0).toDouble();
    return Offset(
      bound(offset.dx, _fitted.width * scale, _viewport.width),
      bound(offset.dy, _fitted.height * scale, _viewport.height),
    );
  }

  void _configureViewport(Size viewport) {
    final source = widget.captureContent != null
        ? widget.captureImageSize ?? viewport
        : _imageSize ?? viewport;
    final fitted = applyBoxFit(BoxFit.contain, source, viewport).destination;
    if (_viewport == viewport && _fitted == fitted) return;
    _animationController.stop();
    _viewport = viewport;
    _fitted = fitted;
    _scale = 1;
    _offset = _boundOffset(Offset.zero, 1);
    _pointerCount = 0;
  }

  void _animateTo(double scale, Offset offset) {
    _animationController.stop();
    _animationStartScale = _scale;
    _animationEndScale = scale;
    _animationStartOffset = _offset;
    _animationEndOffset = _boundOffset(offset, scale);
    _animationController.forward(from: 0);
  }

  void _reset() => _animateTo(1, Offset.zero);

  void _handleDoubleTap() {
    if (_scale > 1.05) {
      _reset();
      return;
    }
    final imagePoint = (_doubleTapPosition - _offset) / _scale;
    _animateTo(2.5, _doubleTapPosition - imagePoint * 2.5);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _animationController.stop();
    _previousFocalPoint = _pointerStartFocalPoint;
    _previousGestureScale = 1;
    _pointerCount = details.pointerCount;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    // Rebase when fingers are added/removed. Flutter changes the focal point
    // and span at that moment; treating it as movement would make the image jump.
    if (_pointerCount != details.pointerCount) {
      _previousFocalPoint = details.localFocalPoint;
      _previousGestureScale = details.scale;
      _pointerCount = details.pointerCount;
      return;
    }
    final nextScale =
        (_scale * details.scale / _previousGestureScale).clamp(1.0, _maxScale);
    final imagePoint = (_previousFocalPoint - _offset) / _scale;
    setState(() {
      _scale = nextScale;
      _offset = _boundOffset(
        details.localFocalPoint - imagePoint * nextScale,
        nextScale,
      );
    });
    _previousGestureScale = details.scale;
    _previousFocalPoint = details.localFocalPoint;
  }

  void _rememberPointer(PointerEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (event is PointerDownEvent) {
      _animationController.stop();
      _rebasePointerFocalPoint();
    }
  }

  void _removePointer(PointerEvent event) {
    _pointers.remove(event.pointer);
    _rebasePointerFocalPoint();
  }

  void _rebasePointerFocalPoint() {
    if (_pointers.isEmpty) return;
    _pointerStartFocalPoint =
        _pointers.values.reduce((a, b) => a + b) / _pointers.length.toDouble();
  }

  Future<void> _retry() async {
    _detachImageListener();
    setState(() {
      _failed = false;
      _imageSize = null;
      _viewport = Size.zero;
    });
    await _provider.evict();
    if (mounted) _resolveImage();
  }

  Widget _imageArea(AppLocalizations l10n) {
    if (_failed) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white70, size: 64),
              const SizedBox(height: 16),
              Text(l10n.imageNotAvailable,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 8),
              Text(l10n.medicalImageLoadError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: _retry,
                  child: Text(l10n.retry,
                      style: const TextStyle(color: Colors.white))),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return LayoutBuilder(builder: (context, constraints) {
      _configureViewport(constraints.biggest);
      return Listener(
        onPointerDown: _rememberPointer,
        onPointerMove: _rememberPointer,
        onPointerUp: _removePointer,
        onPointerCancel: _removePointer,
        child: GestureDetector(
          key: const ValueKey('medical-image-viewport'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onDoubleTapDown: (details) =>
              _doubleTapPosition = details.localPosition,
          onDoubleTap: _handleDoubleTap,
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Transform(
                    alignment: Alignment.topLeft,
                    transform: Matrix4.identity()
                      ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                      ..scaleByDouble(_scale, _scale, 1, 1),
                    child: SizedBox(
                      key: const ValueKey('medical-image-content'),
                      width: _fitted.width,
                      height: _fitted.height,
                      child: widget.captureContent ??
                          Image(
                              image: _provider,
                              fit: BoxFit.fill,
                              errorBuilder: (_, error, stack) =>
                                  const SizedBox.shrink()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFF4F7FA),
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    color: Colors.white70,
                    tooltip: l10n.resetZoom,
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    onPressed: _ready ? _reset : null,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
            Expanded(child: _imageArea(l10n)),
          ],
        ),
      ),
    );
  }
}
