// Сторож подключения сохранения к ленте воспоминаний.
//
// Лист воспоминания — приватный класс в part-файле, собрать его в тесте без
// PocketBase нельзя, поэтому проверяются исходники: старое скачивание не
// вернулось, меню не выходит молча, полный экран знает запись.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final lane = _read('lib/screens/memory_lane_screen.dart');
  final detail = _read('lib/screens/memory_lane/detail.dart');
  final gallery = _read('lib/screens/memory_lane/gallery.dart');
  final all = '$lane\n$detail\n$gallery';

  test('старая кнопка скачивания не вернулась', () {
    // Она открывала браузер для каждого своего файла и брала только обложку.
    expect(all, isNot(contains('_downloadMemoryMedia(')));
    expect(all, isNot(contains('Gal.putImage(')));
    expect(all, isNot(contains('Gal.putVideo(')));
    expect(all, isNot(contains("url.contains('firebase')")));
  });

  test('лист воспоминания сохраняет разделённой кнопкой через общий поток', () {
    expect(detail, contains('SaveSplitButton('));
    expect(detail, contains('saveToGallery('));
    expect(detail, contains('showSaveOptionsSheet('));
    expect(detail, contains('showFramePicker('));
  });

  test('меню «три точки» считает пункты и не выходит молча', () {
    expect(detail, contains('memoryMenuActions('));
    expect(detail, isNot(contains('if (!widget.isOwner && !canSetPlace) return;')));
    // Кнопку без пунктов лист не показывает.
    expect(detail, contains('_menuActions(memory).isNotEmpty'));
  });

  test('каждый полноэкранный просмотр ленты знает запись кадра', () {
    for (final src in [lane, detail, gallery]) {
      final calls = RegExp(r'(?<![\w])FullscreenGallery\(').allMatches(src);
      for (final c in calls) {
        final window = src.substring(c.start, (c.start + 260).clamp(0, src.length));
        if (window.startsWith('FullscreenGallery({')) continue; // конструктор
        expect(window, contains('memoryOf'),
            reason: 'FullscreenGallery без memoryOf: кадр не сохранить');
      }
    }
  });

  test('лента подхватывает оборванную очередь и держит островок', () {
    expect(lane, contains('MediaSaveQueue.instance.resume()'));
    expect(lane, contains('SaveIsland('));
    expect(gallery, contains('SaveIsland('));
  });

  test('выбор нескольких записей: вход из листа, выход кнопкой «Назад»', () {
    expect(lane, contains("trKey('feedSelectMany')"));
    expect(lane, contains('canPop: !_selecting'));
    expect(lane, contains('_saveSelected'));
  });
}
