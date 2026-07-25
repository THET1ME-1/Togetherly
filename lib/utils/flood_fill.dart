import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Заливка области холста.
///
/// Работает в любом режиме — и в обычном рисовании, и в пиксельном: холст
/// сначала растеризуется, а дальше это просто картинка. По-другому область
/// произвольной формы не залить: кривой её не описать, а старый код умел лишь
/// перекрасить целую фигуру или весь фон.
///
/// Считает на несжатых пикселях, поэтому вызывать только по тапу и на холсте
/// размером с экран — не в цикле отрисовки.
class FloodFill {
  const FloodFill._();

  /// Насколько цвет пикселя может отличаться от исходного, чтобы всё ещё
  /// считаться той же областью.
  ///
  /// Ноль не годится: кривые рисуются со сглаживанием, у линии есть полупрозрачная
  /// кромка, и строгое сравнение оставляло бы вокруг заливки светлый ореол.
  static const int defaultTolerance = 32;

  /// Заливает область вокруг точки ([startX], [startY]) цветом [fillColor].
  ///
  /// Возвращает картинку размером с холст, где закрашена только найденная
  /// область, а остальное прозрачно, — её кладут поверх рисунка отдельным
  /// штрихом. null, если заливать нечего (ткнули в уже залитое место).
  static Future<ui.Image?> fill({
    required ui.Image source,
    required int startX,
    required int startY,
    required int fillColor,
    int tolerance = defaultTolerance,
  }) async {
    final width = source.width;
    final height = source.height;
    if (width <= 0 || height <= 0) return null;
    if (startX < 0 || startY < 0 || startX >= width || startY >= height) {
      return null;
    }

    final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final pixels = data.buffer.asUint32List();

    final startIndex = startY * width + startX;
    final target = pixels[startIndex];

    // Цвет с картинки лежит в порядке ABGR, а фильтр приходит как ARGB.
    final fill = _argbToAbgr(fillColor);
    if (_close(target, fill, tolerance)) return null;

    // Результат — прозрачный слой, на котором закрашена только область.
    final out = Uint32List(width * height);

    // Обход в ширину по своему стеку: рекурсия на холсте в миллион пикселей
    // складывает стек вызовов.
    final stack = Int32List(width * height);
    var top = 0;
    stack[top++] = startIndex;

    final visited = Uint8List(width * height);
    visited[startIndex] = 1;

    while (top > 0) {
      final index = stack[--top];
      if (!_close(pixels[index], target, tolerance)) continue;

      out[index] = fill;

      final x = index % width;
      final y = index ~/ width;

      void push(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) return;
        final ni = ny * width + nx;
        if (visited[ni] == 1) return;
        visited[ni] = 1;
        stack[top++] = ni;
      }

      // Только четыре соседа: по диагонали заливка просачивается сквозь
      // тонкие линии, нарисованные под углом.
      push(x + 1, y);
      push(x - 1, y);
      push(x, y + 1);
      push(x, y - 1);
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      out.buffer.asUint8List(),
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Похожи ли цвета. Прозрачность учитываем отдельно: прозрачный пиксель и
  /// белый — разные вещи, хотя по трём каналам могут совпасть.
  static bool _close(int a, int b, int tolerance) {
    if (a == b) return true;
    final aa = (a >> 24) & 0xFF;
    final ba = (b >> 24) & 0xFF;
    if ((aa - ba).abs() > tolerance) return false;
    // Оба прозрачные — считаем одинаковыми, какого бы цвета ни были каналы.
    if (aa < 8 && ba < 8) return true;

    final dr = (((a >> 16) & 0xFF) - ((b >> 16) & 0xFF)).abs();
    final dg = (((a >> 8) & 0xFF) - ((b >> 8) & 0xFF)).abs();
    final db = ((a & 0xFF) - (b & 0xFF)).abs();
    return dr <= tolerance && dg <= tolerance && db <= tolerance;
  }

  /// 0xAARRGGBB → 0xAABBGGRR: у растра каналы идут в обратном порядке.
  static int _argbToAbgr(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return (a << 24) | (b << 16) | (g << 8) | r;
  }
}
