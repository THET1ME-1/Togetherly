import 'package:flutter/material.dart';

/// Кадр, который увеличивают щипком, и который говорит, увеличен ли он.
///
/// Просмотру это нужно ради жеста «потянуть вниз»: у кадра в обычном размере
/// он закрывает просмотр, а у увеличенного палец двигает сам снимок.
class ZoomablePhoto extends StatefulWidget {
  const ZoomablePhoto({
    super.key,
    required this.onZoomChanged,
    this.minScale = 0.5,
    this.maxScale = 4.0,
    required this.child,
  });

  final ValueChanged<bool> onZoomChanged;
  final double minScale;
  final double maxScale;
  final Widget child;

  /// С какого увеличения кадр считается увеличенным: дрожь пальцев при
  /// касании двумя пальцами за увеличение не считается.
  static const double zoomedFrom = 1.02;

  @override
  State<ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<ZoomablePhoto> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_check);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    final zoomed =
        _controller.value.getMaxScaleOnAxis() > ZoomablePhoto.zoomedFrom;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      child: widget.child,
    );
  }
}
