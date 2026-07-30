import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Куда упирается пропорция листа.
///
/// Панораму 4:1 делить пополам бессмысленно: половина выходит уже пальца, и
/// рисовать в ней нечем. Лист приводится к этим границам, а картинка вписыв
/// ается внутрь.
const double kColoringMaxRatio = 2.0;

/// Длинная сторона готового контура. Больше держать незачем: контур рисуется
/// поверх холста размером с экран, а память на телефоне не бесконечная.
const int kColoringMaxSide = 1600;

/// Ниже этой яркости пиксель считается линией. Выше — фоном.
const int _lineThreshold = 200;

/// Подготовленный контур раскраски.
class ColoringOutline {
  const ColoringOutline({
    required this.png,
    required this.width,
    required this.height,
    required this.ratio,
    required this.leaks,
  });

  /// PNG с прозрачным фоном и тёмными линиями.
  final Uint8List png;

  final int width;
  final int height;

  /// Пропорция листа (ширина к высоте), уже с оглядкой на [kColoringMaxRatio].
  final double ratio;

  /// Течёт ли заливка. true — в контуре есть разрыв: краска разольётся по
  /// всему листу, и человеку об этом лучше сказать до начала рисования.
  final bool leaks;
}

/// Готовит загруженную картинку к роли раскраски.
///
/// Три вещи, без которых она не работает:
///  * фон становится прозрачным — контур рисуется ПОВЕРХ мазков, и белый лист
///    закрыл бы собой всё нарисованное;
///  * линии дожимаются до тёмного — заливка проскакивает сквозь бледные и
///    полупрозрачные штрихи;
///  * проверяется замкнутость — [ColoringOutline.leaks].
///
/// Функция чистая и не знает про Flutter: её гоняют и в тестах, и в отдельном
/// isolate, чтобы обработка не морозила интерфейс.
///
/// Бросает [FormatException], если это не картинка.
ColoringOutline prepareColoringOutline(List<int> bytes) {
  // Пакет на мусорных байтах бросает своё исключение, а иногда и RangeError.
  // Наружу отдаём одно понятное: вызывающему нужно показать человеку «это не
  // картинка», а не разбирать чужие типы ошибок.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(Uint8List.fromList(bytes));
  } catch (_) {
    throw const FormatException('не удалось разобрать картинку');
  }
  if (decoded == null) {
    throw const FormatException('не удалось разобрать картинку');
  }

  // Ужимаем заранее: дальше идёт попиксельный проход и заливка, а на снимке
  // 4000×3000 это секунды даже в isolate.
  final scaled = (decoded.width > kColoringMaxSide ||
          decoded.height > kColoringMaxSide)
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? kColoringMaxSide : null,
          height: decoded.height > decoded.width ? kColoringMaxSide : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  final out = img.Image(width: scaled.width, height: scaled.height, numChannels: 4);
  for (var y = 0; y < scaled.height; y++) {
    for (var x = 0; x < scaled.width; x++) {
      final p = scaled.getPixel(x, y);
      final lum = img.getLuminance(p).round();
      if (lum >= _lineThreshold) {
        out.setPixelRgba(x, y, 0, 0, 0, 0); // фон
        continue;
      }
      // Чем темнее пиксель, тем плотнее линия. Мягкий край сохраняет
      // сглаживание рисунка и не превращает его в лесенку.
      final alpha = (((_lineThreshold - lum) / _lineThreshold) * 255)
          .round()
          .clamp(60, 255);
      out.setPixelRgba(x, y, 20, 20, 20, alpha);
    }
  }

  final ratio = (scaled.width / scaled.height)
      .clamp(1 / kColoringMaxRatio, kColoringMaxRatio)
      .toDouble();

  return ColoringOutline(
    png: img.encodePng(out),
    width: scaled.width,
    height: scaled.height,
    ratio: ratio,
    leaks: _leaks(out),
  );
}

/// Течёт ли заливка сквозь контур.
///
/// Разливаем «фон» от четырёх углов по прозрачным пикселям. У замкнутой фигуры
/// внутренности с внешним фоном не связаны, поэтому непролитые прозрачные
/// пиксели останутся. Если залилось всё до единого — замкнутых областей нет,
/// и краска в приложении растечётся по всему листу.
bool _leaks(img.Image im) {
  final w = im.width, h = im.height;
  final visited = Uint8List(w * h);
  final stack = <int>[];

  bool isBackground(int x, int y) => im.getPixel(x, y).a < 32;

  for (final corner in [[0, 0], [w - 1, 0], [0, h - 1], [w - 1, h - 1]]) {
    final x = corner[0], y = corner[1];
    if (isBackground(x, y) && visited[y * w + x] == 0) {
      stack.add(y * w + x);
      visited[y * w + x] = 1;
    }
  }

  var filled = 0;
  while (stack.isNotEmpty) {
    final idx = stack.removeLast();
    filled++;
    final x = idx % w, y = idx ~/ w;
    for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      final nx = x + d[0], ny = y + d[1];
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final ni = ny * w + nx;
      if (visited[ni] != 0 || !isBackground(nx, ny)) continue;
      visited[ni] = 1;
      stack.add(ni);
    }
  }

  var background = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (isBackground(x, y)) background++;
    }
  }

  // Полностью пустая картинка (одни линии или один фон) — тоже негодная.
  if (background == 0) return true;
  return filled >= background;
}
