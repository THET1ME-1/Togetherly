import 'dart:ui';

/// Числа раскладки виджета «Вместе»: растр фона и дорожка вех.
///
/// Виджет рисуется трижды — Kotlin (`WidgetImages.halftone` и `trackLine`),
/// Swift (`TgHalftone`, `TgTrackLine`) и здесь, для превью в каталоге. Числа
/// живут в одном месте, а сторож `test/models/together_track_spec_test.dart`
/// сверяет, что натив не разошёлся с ними: расхождение видно только на
/// устройстве и выглядит как «в приложении одно, на столе другое».
class TogetherTrackSpec {
  const TogetherTrackSpec._();

  /// Шаг сетки растра в dp и радиус самой крупной точки.
  static const double dotStep = 15;
  static const double dotMaxRadius = 5.2;

  /// Доля расстояния до дальнего угла, с которой точки начинают проявляться:
  /// левый верх остаётся чистым, там лежит число.
  static const double dotStart = 0.18;

  /// Точка мельче этого не рисуется: пыль на фоне читается как шум.
  static const double dotMin = 0.5;

  /// Прозрачность точек. Непрозрачный растр на 2×2 превращался в горошек и
  /// спорил с числом — на большой ячейке это было незаметно.
  static const double dotOpacity = 0.55;

  /// Дорожка: поля по краям, толщина линии и радиусы отметок.
  static const double trackPad = 9;
  static const double trackStroke = 5;
  static const double stopRadius = 6;
  static const double todayRadius = 7;
  static const double todayRing = 9.5;

  /// Вертикальная лента на большом размере.
  static const double columnStroke = 4;
  static const double columnWidth = 24;
}

/// Точки растра для прямоугольника [size]: радиус растёт к дальнему углу.
///
/// Та же формула, что в нативе: доля расстояния от левого верха к правому
/// низу минус [TogetherTrackSpec.dotStart], умноженная на максимальный радиус.
List<({Offset center, double radius})> togetherHalftoneDots(Size size) {
  final out = <({Offset center, double radius})>[];
  if (size.width <= 0 || size.height <= 0) return out;
  final far = Offset(size.width, size.height).distance;
  const step = TogetherTrackSpec.dotStep;
  for (var y = step / 2; y < size.height; y += step) {
    for (var x = step / 2; x < size.width; x += step) {
      final t = Offset(x, y).distance / far;
      final r = (t - TogetherTrackSpec.dotStart) * TogetherTrackSpec.dotMaxRadius;
      if (r < TogetherTrackSpec.dotMin) continue;
      out.add((center: Offset(x, y), radius: r));
    }
  }
  return out;
}

/// Центры отметок вертикальной ленты: [rows] строк, точка — в середине своей.
List<double> togetherColumnStops(int rows) =>
    [for (var i = 0; i < rows; i++) (i + 0.5) / rows];
