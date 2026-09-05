// Пустой фото-виджет обязан называть себя своим именем.
//
// «Фото-виджет» и «Фото партнёра» — наследники «Фото дня» и рисуют его
// разметку, где заголовок и подпись вшиты намертво: «Фото дня» и «Нет
// воспоминаний». Пока фото не доехали, человек видит на столе чужую вывеску и
// не узнаёт свой виджет.
//
// Ровно это и случилось у @hi_no_kate (04.09.2026). Сохранение зависало на
// нативном кодеке, виджет оставался пустым — а на рабочем столе стояла плашка
// «Фото дня · Нет воспоминаний». Вывод человека закономерный: «виджет
// отображается как добавленный, но на рабочем столе его нет», и она добавляла
// новый экземпляр за экземпляром.
//
// Слова пишет приложение — оно одно знает язык человека; в разметке остаётся
// прежний текст на случай, если ключей ещё нет.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final layout =
      File('android/app/src/main/res/layout/photo_day_widget.xml')
          .readAsStringSync();
  final provider = File(
    'android/app/src/main/kotlin/com/togetherly/love/PhotoDayWidgetProvider.kt',
  ).readAsStringSync();
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  test('у заголовка и подписи есть id — иначе их нечем заменить', () {
    expect(layout.contains('android:id="@+id/photo_empty_title"'), isTrue);
    expect(layout.contains('android:id="@+id/photo_empty_hint"'), isTrue);
  });

  test('виджет берёт слова из контейнера', () {
    expect(provider.contains('_empty_title'), isTrue);
    expect(provider.contains('_empty_hint'), isTrue);
    expect(provider.contains('setTextViewText(R.id.photo_empty_title'), isTrue);
    expect(provider.contains('setTextViewText(R.id.photo_empty_hint'), isTrue);
  });

  test('приложение пишет эти слова', () {
    // Ключ собирается из номера экземпляра: `photo_day_widget_<id>_empty_title`.
    // Проверяем суффикс и то, что он уходит в контейнер, а не просто лежит
    // строкой: ключ, который виджет читает, а приложение не пишет, уже оставлял
    // четыре фото-виджета белыми (история ios_* ключей).
    expect(dart.contains("'empty_title'"), isTrue,
        reason: 'ключ читается виджетом, но никем не пишется');
    expect(dart.contains("'empty_hint'"), isTrue);
    final i = dart.indexOf("'empty_title'");
    expect(dart.substring(i - 400, i).contains('saveWidgetData'), isTrue,
        reason: 'слова должны уезжать в контейнер виджета');
  });

  test('слова переведены, а не вшиты в код', () {
    expect(dart.contains('photoWidgetEmptyTitleMine'), isTrue);
    expect(dart.contains('photoWidgetEmptyTitlePartner'), isTrue);
    expect(dart.contains('photoWidgetEmptyHintMine'), isTrue);
    expect(dart.contains('photoWidgetEmptyHintPartner'), isTrue);
  });
}
