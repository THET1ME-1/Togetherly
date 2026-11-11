import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/coloring_adopted.dart';

/// Свою раскраску партнёр видел только при первом заходе на лист (обращение
/// 617, 11.11.2026: «у партнёра при рисовании исчезает раскраска»). Картинку
/// экран узнавал в момент скачивания контура. Вышел и вернулся — файл уже на
/// диске, качать нечего, а в очереди загрузок этого телефона картинки нет: её
/// загружал другой. Лист открывался обычным холстом 1600×1600.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('coloring_adopted'));
  tearDown(() => dir.deleteSync(recursive: true));

  // Заголовок PNG с нужным размером: дальше него правило не читает.
  File outline(String name, int width, int height) {
    final head = ByteData(24);
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < 8; i++) {
      head.setUint8(i, signature[i]);
    }
    head.setUint32(8, 13);
    'IHDR'.codeUnits.asMap().forEach((i, c) => head.setUint8(12 + i, c));
    head.setUint32(16, width);
    head.setUint32(20, height);
    return File('${dir.path}/$name')
      ..writeAsBytesSync(head.buffer.asUint8List());
  }

  test('скачанный у партнёра контур узнаётся при повторном заходе', () {
    final picture = adoptedColoring(
      outline('own_1794428401822.png', 1205, 1280),
      id: 'own_1794428401822',
      title: 'Своя раскраска',
    );
    expect(picture, isNotNull);
    expect(picture!.isOwn, isTrue);
    expect(picture.title, 'Своя раскраска');
    expect(picture.ownRatio, closeTo(1205 / 1280, 1e-9));
  });

  test('контура на диске нет — картинки нет', () {
    final picture = adoptedColoring(
      File('${dir.path}/own_1.png'),
      id: 'own_1',
      title: 'Своя раскраска',
    );
    expect(picture, isNull);
  });

  test('оборванный или чужой файл картинкой не считается', () {
    final broken = File('${dir.path}/own_2.png')..writeAsStringSync('<html>');
    expect(adoptedColoring(broken, id: 'own_2', title: 'x'), isNull);
    expect(
        adoptedColoring(outline('own_3.png', 0, 1280), id: 'own_3', title: 'x'),
        isNull);
  });

  test('встроенная картинка с диска не берётся', () {
    expect(
        adoptedColoring(outline('cafe.png', 1600, 1600),
            id: 'cafe', title: 'x'),
        isNull);
  });

  test('экран ищет скачанный контур, когда картинки нет в своей очереди', () {
    final screen = File('lib/screens/draw_screen.dart').readAsStringSync();
    final start = screen.indexOf('Future<void> _ensureOwnColorings()');
    final end = screen.indexOf('Future<void> _loadColoringOutline()');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    expect(screen.substring(start, end), contains('adoptedColoring('));
  });
}
