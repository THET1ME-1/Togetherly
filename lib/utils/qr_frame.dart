import 'dart:typed_data';

/// Разбор кадра камеры для декодера QR.
///
/// Модель распознавания ML Kit из сборок вне Google убрана: движок там
/// нативный, скачать его неоткуда, а тащить 5,5 МБ ради одного экрана дорого.
/// Вместо него читает чистый Dart (`zxing2`), и вот сюда приходит кадр.
///
/// Камера отдаёт YUV420: первая плоскость — яркость, по байту на точку. Для
/// чёрно-белого квадрата этого достаточно, цветность не нужна вовсе.

/// Доля короткой стороны кадра, которую занимает окно наведения.
///
/// Живёт здесь, а не рядом с рисунком рамки: по этому числу и рисуют окно, и
/// режут кадр. Разъедутся — человек будет наводить код в одну область, а
/// читаться будет другая.
const double kQrWindowFraction = 0.72;

/// Квадрат в кадре, который отдаём декодеру.
class CropRect {
  final int left;
  final int top;
  final int side;

  const CropRect({required this.left, required this.top, required this.side});
}

/// Картинка для `RGBLuminanceSource`: сторона и пиксели ARGB.
class QrFramePixels {
  final int side;
  final Int32List pixels;

  const QrFramePixels(this.side, this.pixels);
}

/// Центральный квадрат кадра со стороной [fraction] от короткой стороны.
///
/// Доля должна совпадать с окном видоискателя на экране: человек наводит код в
/// нарисованную рамку и вправе ждать, что читают ровно её. Заодно меньше
/// работы на кадр и меньше мусора по краям, за который цепляется бинаризация.
CropRect cropSquare({
  required int width,
  required int height,
  double fraction = 1.0,
}) {
  final short = width < height ? width : height;
  final side = (short * fraction.clamp(0.1, 1.0)).round();
  return CropRect(
    left: (width - side) ~/ 2,
    top: (height - side) ~/ 2,
    side: side,
  );
}

/// Собирает из плоскости яркости серую картинку под декодер.
///
/// [bytesPerRow] у камеры почти всегда больше ширины кадра — за краем лежит
/// выравнивание, и читать его нельзя, иначе картинка «поедет» по диагонали.
///
/// [maxSide] прореживает крупный кадр: QR из шести символов читается и с 300
/// точек, а полный кадр 1080×1080 — это миллион int32 на каждый разбор.
///
/// [bytesPerPixel] — сколько байт занимает точка: у YUV420 на Android один
/// (плоскость яркости), у BGRA на iOS четыре, и там берётся первый канал.
QrFramePixels luminanceToPixels({
  required Uint8List bytes,
  required int bytesPerRow,
  required CropRect crop,
  required int maxSide,
  int bytesPerPixel = 1,
}) {
  // Шаг целый: дробный давал бы разное число столбцов в разных строках.
  final step = crop.side > maxSide ? (crop.side / maxSide).ceil() : 1;
  final side = (crop.side / step).floor();
  final pixels = Int32List(side * side);

  var i = 0;
  for (var y = 0; y < side; y++) {
    final row = (crop.top + y * step) * bytesPerRow;
    for (var x = 0; x < side; x++) {
      final index = row + (crop.left + x * step) * bytesPerPixel;
      // Последняя строка у некоторых камер короче обещанного — читаем
      // осторожно, чтобы кадр не ронял экран.
      final v = index < bytes.length ? bytes[index] : 0;
      pixels[i++] = 0xFF000000 | (v << 16) | (v << 8) | v;
    }
  }
  return QrFramePixels(side, pixels);
}
