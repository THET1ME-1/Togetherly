import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chest/chest_frames.dart';

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
}
