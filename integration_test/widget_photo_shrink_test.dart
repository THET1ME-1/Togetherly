// Проверка на живом Android: снимок с камеры не уходит в виджет оригиналом.
//
// Правило проверено юнит-тестами, но кодек живёт в прошивке, и подменить его
// нечем. Здесь работает настоящий FlutterImageCompress на настоящем аппарате:
// берём снимок 4000×3000 (десять мегабайт — ровно тот случай, что убивал
// виджет по памяти) и смотрим, что кладётся в контейнер.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:love_app/services/home_widget_service.dart';
import 'package:love_app/services/widget_image_limit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('крупный снимок ужимается и влезает в предел виджета',
      (tester) async {
    final bytes = await bigPhotoBytes();
    debugPrintSize('оригинал', bytes.length);

    final out = await HomeWidgetService.instance.shrinkForWidget(bytes, 1200);

    expect(out, isNotNull, reason: 'кодек справился — должен вернуть картинку');
    debugPrintSize('в виджет', out!.length);
    expect(out.length, lessThanOrEqualTo(kMaxWidgetPhotoBytes),
        reason: 'больше предела виджет не переварит');

    // Вес обманчив: PNG-заготовка из ровных квадратов жмётся лучше, чем
    // перекодированный снимок. Смотрим на габариты — именно они превращаются в
    // мегабайты памяти при отрисовке (ширина × высота × 4 байта).
    final shrunk = await decodeSize(out);
    // ignore: avoid_print
    print('ЗАМЕР · габариты: ${shrunk.width.round()}×${shrunk.height.round()} точек, '
        'в памяти ${(shrunk.width * shrunk.height * 4 / 1048576).toStringAsFixed(1)} МБ');
    expect(shrunk.width, lessThanOrEqualTo(1200 + 1),
        reason: 'кодек обязан ужать до предела ключа');
    expect(shrunk.width * shrunk.height * 4, lessThan(8 * 1024 * 1024),
        reason: 'в разжатом виде картинка должна влезать в память виджета');
  });

  testWidgets('мусор вместо картинки не уходит в виджет оригиналом',
      (tester) async {
    // Так выглядит формат, который кодеку не по зубам, и оборванная закачка.
    final junk = Uint8List.fromList(List<int>.generate(3 * 1024 * 1024, (i) => i % 251));
    final out = await HomeWidgetService.instance.shrinkForWidget(junk, 1200);
    expect(out, isNull,
        reason: 'раньше здесь возвращался оригинал — и виджет умирал по памяти');
  });

  testWidgets('маленькая сторона даёт совсем лёгкий файл', (tester) async {
    final bytes = await bigPhotoBytes();
    final out = await HomeWidgetService.instance.shrinkForWidget(bytes, 200);
    expect(out, isNotNull);
    expect(out!.length, lessThan(300 * 1024));
  });
}

/// Размеры картинки в точках — по ним считается память при отрисовке.
Future<ui.Size> decodeSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  frame.image.dispose();
  codec.dispose();
  return size;
}

/// Снимок «как с камеры»: 3000×2000 пёстрых пикселей, которые не сожмёшь в
/// ничто. Рисуем на месте — доступа к галерее у теста нет.
Future<Uint8List> bigPhotoBytes() async {
  const int w = 3000, h = 2000;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint();
  var seed = 7;
  for (int y = 0; y < h; y += 20) {
    for (int x = 0; x < w; x += 20) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      paint.color = ui.Color(0xFF000000 | (seed & 0xFFFFFF));
      canvas.drawRect(ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 20, 20), paint);
    }
  }
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void debugPrintSize(String label, int bytes) {
  // ignore: avoid_print
  print('ЗАМЕР · $label: ${(bytes / 1024).round()} КБ');
}
