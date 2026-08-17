import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож обновления раздела «Смотрим».
///
/// Коллекция `watch_videos` в рассылку пары не входит: живого события о новом
/// ролике партнёру не приходит. Список читался ровно один раз, в `initState`,
/// и пока оба сидели в разделе, залитый ролик у второго не появлялся ничем —
/// ни сам, ни по жесту. Отсюда жалоба «поставил видео, а партнёр не видит его»
/// (16.08.2026).
///
/// Пока рассылки нет, экран обязан давать два пути к свежему списку: жест вниз
/// и возврат приложения из фона. Уберут любой — вернётся та же жалоба.
void main() {
  final source =
      File('lib/screens/together/watch_home_screen.dart').readAsStringSync();

  test('список тянется вниз', () {
    expect(
      source.contains('RefreshIndicator'),
      isTrue,
      reason: 'Без жеста обновить раздел нечем: живых событий по watch_videos '
          'не приходит.',
    );
    expect(
      source.contains('AlwaysScrollableScrollPhysics'),
      isTrue,
      reason: 'На коротком списке жест не родится без этой физики.',
    );
  });

  test('возврат из фона перечитывает ролики', () {
    expect(
      source.contains('didChangeAppLifecycleState'),
      isTrue,
      reason: 'Партнёр сворачивает приложение и возвращается — список обязан '
          'освежиться.',
    );
    expect(
      source.contains('AppLifecycleState.resumed'),
      isTrue,
      reason: 'Обновление вешается именно на возврат, а не на любое состояние.',
    );
    expect(
      source.contains('WidgetsBinding.instance.addObserver(this)') &&
          source.contains('WidgetsBinding.instance.removeObserver(this)'),
      isTrue,
      reason: 'Наблюдатель жизненного цикла ставится и снимается парой.',
    );
  });
}
