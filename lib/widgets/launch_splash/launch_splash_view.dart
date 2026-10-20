import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../models/launch_splash.dart';
import 'launch_splash_painter.dart';

/// Заставка от начала до конца. Время идёт от первого кадра, а не от
/// создания виджета: иначе медленный первый кадр съел бы начало сцены.
/// По концу зовёт [onDone] один раз.
class LaunchSplashView extends StatefulWidget {
  const LaunchSplashView({super.key, required this.splash, required this.images, this.onDone});

  final LaunchSplash splash;
  final Map<String, ui.Image> images;
  final VoidCallback? onDone;

  @override
  State<LaunchSplashView> createState() => _LaunchSplashViewState();
}

class _LaunchSplashViewState extends State<LaunchSplashView> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _ms = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_tick);
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final ms = elapsed.inMicroseconds / 1000;
    if (ms < widget.splash.ms) {
      _ms.value = ms;
      return;
    }
    _ticker.stop();
    _ms.value = widget.splash.ms.toDouble();
    if (_done) return;
    _done = true;
    widget.onDone?.call();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: LaunchSplashPainter(splash: widget.splash, images: widget.images, ms: _ms),
        size: Size.infinite,
      ),
    );
  }
}
