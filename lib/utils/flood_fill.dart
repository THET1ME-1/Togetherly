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

  /// На сколько пикселей залезать под контур. Два — кромка сглаживания у линии
  /// толщиной около семи пикселей; больше начинает выпирать из-под тонких.
  static const int defaultBleed = 2;

  /// Заливает область вокруг точки ([startX], [startY]) цветом [fillColor].
  ///
  /// Возвращает картинку размером с холст, где закрашена только найденная
  /// область, а остальное прозрачно, — её кладут поверх рисунка отдельным
  /// штрихом. null, если заливать нечего (ткнули в уже залитое место).
  /// Границы закрашенной области — левый/верхний/правый/нижний непрозрачные
  /// пиксели. null — слой пустой.
  ///
  /// Нужно, чтобы не тащить на сервер прозрачный слой во весь холст: заливка
  /// одной юбки весила столько же, сколько весь рисунок.
  static Future<ui.Rect?> opaqueBounds(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final pixels = data.buffer.asUint32List();
    final w = image.width, h = image.height;

    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        // Альфа лежит в старшем байте ABGR-пикселя.
        if ((pixels[row + x] >> 24) == 0) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < 0) return null;
    return ui.Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  static Future<ui.Image?> fill({
    required ui.Image source,
    required int startX,
    required int startY,
    required int fillColor,
    int tolerance = defaultTolerance,
    int bleed = defaultBleed,
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

    _bleed(out, width, height, fill, bleed);

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

  /// Расширяет залитое пятно на [steps] пикселей во все стороны.
  ///
  /// Без этого вдоль каждой линии оставался светлый ободок: контур нарисован со
  /// сглаживанием, его полупрозрачная кромка по цвету уже не белая, и заливка
  /// до неё не доходит. Лишние пиксели прячутся под самим контуром — он лежит
  /// поверх мазков, — поэтому расширять безопаснее, чем повышать допуск:
  /// допуск начинает просачиваться сквозь тонкие линии.
  static void _bleed(Uint32List out, int width, int height, int fill, int steps) {
    if (steps <= 0) return;
    for (var pass = 0; pass < steps; pass++) {
      // Копия нужна, иначе расширение пойдёт лавиной внутри одного прохода.
      final source = Uint32List.fromList(out);
      for (var y = 0; y < height; y++) {
        final row = y * width;
        for (var x = 0; x < width; x++) {
          final index = row + x;
          if (source[index] != 0) continue;
          final up = y > 0 && source[index - width] == fill;
          final down = y < height - 1 && source[index + width] == fill;
          final left = x > 0 && source[index - 1] == fill;
          final right = x < width - 1 && source[index + 1] == fill;
          if (up || down || left || right) out[index] = fill;
        }
      }
    }
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
