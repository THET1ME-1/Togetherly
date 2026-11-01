import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';

/// Неподвижная картинка в один кадр, как фон карточки осеннего сундука.
Future<List<int>> stillPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 60, 52), ui.Paint()..color = const ui.Color(0xFFF5D6A8));
  final image = await recorder.endRecording().toImage(60, 52);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// Карточка сезонного сундука (файл 600 точек) распаковывалась под ширину
// экрана, около 1000 точек: растягивание шло процессором на каждом кадре, и
// на средних телефонах тормозил весь экран сундука (обращение 551).
void main() {
  test('кадр не распаковывается крупнее файла', () {
    expect(chestDecodeWidth(fileWidth: 600, wanted: 1000), 600);
  });

  test('крупный файл ужимается под экран', () {
    expect(chestDecodeWidth(fileWidth: 720, wanted: 500), 500);
  });

  test('ширина файла неизвестна — как раньше, под экран', () {
    expect(chestDecodeWidth(fileWidth: 0, wanted: 800), 800);
  });

  // Неподвижная картинка разжимается при первом кадре, а не при создании
  // декодера. Закрытый сразу описатель оставлял её пустой: у осеннего
  // сундука пропал фон карточки (сборка 264), анимации это не задевало.
  test('неподвижная картинка в один кадр показывается', () async {
    final codec = await chestCodec(Uint8List.fromList(await stillPng()), wanted: 1000);
    final frame = await codec.getNextFrame();
    expect(codec.frameCount, 1);
    expect(frame.image.width, 60);
  });
}
