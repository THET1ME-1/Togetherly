import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/launch_splash.dart';

/// Кадр заставки на момент [ms]: ночь со слоями, окно-сердце, прорезанное в
/// ней, рамка окна и слои поверх. Где окно прорезало ночь, рисунок
/// прозрачный: там уже видно приложение под заставкой.
///
/// Сцена нарисована на экране [LaunchSplash.design] (360×780). На другом
/// экране она растягивается по ширине и встаёт по середине высоты; ночь и
/// слои во весь экран (дверь) закрывают его целиком.
class LaunchSplashPainter extends CustomPainter {
  LaunchSplashPainter({required this.splash, required this.images, required this.ms}) : super(repaint: ms);

  final LaunchSplash splash;

  /// Картинки по имени файла. Чего нет, того на кадре просто нет.
  final Map<String, ui.Image> images;

  final ValueListenable<double> ms;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final now = ms.value;
    final k = size.width / splash.design.width;
    final top = (size.height - splash.design.height * k) / 2;
    final window = splashPoseAt(splash.window.track, splash.step, now);

    // Ночь со всем, что в ней лежит, — отдельным слоем: окно вырезается
    // только из него, а не из приложения под заставкой.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = splash.night);
    for (final layer in splash.layers) {
      if (layer.under) _layer(canvas, size, layer, k, top, now);
    }
    if (window.scale > 0) {
      canvas.drawPath(_windowPath(window, k, top), Paint()..blendMode = BlendMode.clear);
    }
    canvas.restore();

    if (window.scale > 0) {
      // Рамка окна не толстеет вместе с окном: толщина задана в точках сцены.
      final path = _windowPath(window, k, top);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(path, stroke
        ..strokeWidth = splash.window.frameWidth * k
        ..color = const Color(0xFFFFFFFF));
      canvas.drawPath(path, stroke
        ..strokeWidth = splash.window.inkWidth * k
        ..color = splash.window.ink);
    }

    for (final layer in splash.layers) {
      if (!layer.under) _layer(canvas, size, layer, k, top, now);
    }
  }

  Path _windowPath(SplashPose pose, double k, double top) {
    final s = k * pose.scale;
    final matrix = Matrix4.identity()
      ..translateByDouble(k * pose.x, top + k * pose.y, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    return splash.window.path.transform(matrix.storage);
  }

  void _layer(Canvas canvas, Size size, SplashLayer layer, double k, double top, double now) {
    final sprite = splash.sprites[layer.sprite];
    if (sprite == null) return;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (layer.fill) {
      final image = images[sprite.frames.first];
      if (image == null) return;
      canvas.drawImageRect(image, _whole(image), Offset.zero & size, paint);
      return;
    }
    final pose = splashPoseAt(layer.track, splash.step, now);
    if (pose.opacity <= 0 || pose.scale <= 0) return;
    final image = images[sprite.frames[pose.frame.clamp(0, sprite.frames.length - 1)]];
    if (image == null) return;
    if (pose.opacity < 1) paint.color = Color.fromRGBO(255, 255, 255, pose.opacity);
    canvas.save();
    canvas.translate(k * pose.x, top + k * pose.y);
    canvas.scale(k * pose.scale);
    canvas.rotate(pose.rotation * math.pi / 180);
    canvas.drawImageRect(image, _whole(image), sprite.box, paint);
    canvas.restore();
  }

  Rect _whole(ui.Image image) => Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  @override
  bool shouldRepaint(LaunchSplashPainter old) =>
      old.splash != splash || old.images != images || old.ms != ms;
}
