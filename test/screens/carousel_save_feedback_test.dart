// Сохранение фото-виджета не имеет права висеть молча.
//
// Жалоба @hi_no_kate (04.09.2026): «После добавления фото бесконечная
// загрузка». На видео кнопка «Сохранить» превращается в крутящийся кружок и
// остаётся им. Корень — зависший нативный кодек (см.
// `test/services/image_compress_timeout_test.dart`), но само устройство
// ожидания тоже виновато, и двумя способами.
//
// Первый: лист ждал ВСЮ цепочку обновления виджета — скачать каждое фото,
// ужать, положить в контейнер. Восемь снимков по мобильной сети — это минуты,
// в течение которых человек смотрит на спиннер и не знает, работает ли оно.
// Набор сохраняется мгновенно, а обновление виджета доделает себя само.
//
// Второй: отказ уходил в `debugPrint`. Спиннер гас, лист не закрывался, и
// человек оставался без единого слова о том, что случилось.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File('lib/screens/widget_screen.dart').readAsStringSync();
  final editor =
      File('lib/screens/home/widgets/photo_day_carousel_editor.dart')
          .readAsStringSync();

  String bodyOf(String source, String signature, String until) {
    final start = source.indexOf(signature);
    if (start < 0) throw StateError('пропало: $signature');
    final end = source.indexOf(until, start + signature.length);
    return source.substring(start, end > 0 ? end : source.length);
  }

  test('сохранение не ждёт обновления виджета дольше предела', () {
    final body = bodyOf(
      screen,
      'Future<void> _saveCarouselForWidget(',
      'Future<void> _savePhotosForPartner(',
    );
    expect(body.contains('refreshPhotoOfDay'), isTrue);
    expect(body.contains('.timeout('), isTrue,
        reason: 'иначе лист держит человека, пока качаются все снимки');
  });

  test('отказ виден человеку, а не только в журнале', () {
    final body = bodyOf(editor, 'Future<void> _save(', 'Widget build(');
    expect(body.contains('_saveError'), isTrue,
        reason: 'спиннер гас, и человек оставался без объяснения');
  });

  test('сообщение об отказе показано на листе', () {
    expect(editor.contains('_saveError'), isTrue);
    expect(editor.contains('carouselSaveFailed'), isTrue,
        reason: 'нужна строка на языке человека, а не текст исключения');
  });
}
