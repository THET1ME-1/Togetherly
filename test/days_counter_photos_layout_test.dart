// Виджет «Дни вместе» рисуется двумя разметками: с рисунком пары и со своими
// фотографиями. Вторая появилась из-за жалобы @qwinken (25.08.2026): «когда
// выбираешь показывать свои фото — дату не видно». В общей разметке колонка с
// числом и датой стоит по центру, а круглые снимки — внизу; на невысокой
// ячейке дата ложилась прямо на снимок.
//
// Тест стережёт два условия, которые ломаются молча:
//  * RemoteViews падает на действии с неизвестным id — значит каждый
//    `R.id.…` из провайдера должен быть в ОБЕИХ разметках;
//  * в фотоварианте текст не должен снова сползти в зону снимков.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _f(String path) => File(path);

Set<String> _idsUsedByProvider() {
  final src = _f(
    'android/app/src/main/kotlin/com/togetherly/love/DaysCounterWidgetProvider.kt',
  ).readAsStringSync();
  return RegExp(r'R\.id\.(\w+)')
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();
}

Set<String> _idsInLayout(String name) {
  final src = _f('android/app/src/main/res/layout/$name.xml').readAsStringSync();
  return RegExp(r'android:id="@\+?id/(\w+)"')
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  test('обе разметки знают все id, которыми пользуется провайдер', () {
    final used = _idsUsedByProvider();
    for (final layout in ['days_counter_widget', 'days_counter_widget_photos']) {
      final have = _idsInLayout(layout);
      expect(
        used.difference(have),
        isEmpty,
        reason: 'в $layout.xml нет этих id — RemoteViews бросит исключение и '
            'на рабочем столе появится «Невозможно загрузить виджет»',
      );
    }
  });

  test('провайдер выбирает разметку по наличию снимков', () {
    final src = _f(
      'android/app/src/main/kotlin/com/togetherly/love/DaysCounterWidgetProvider.kt',
    ).readAsStringSync();
    expect(src.contains('R.layout.days_counter_widget_photos'), isTrue);
    expect(
      src.indexOf('val layoutId'),
      lessThan(src.indexOf('RemoteViews(context.packageName, layoutId)')),
      reason: 'разметку выбираем ДО сборки RemoteViews',
    );
  });

  group('разметка со снимками', () {
    final src =
        _f('android/app/src/main/res/layout/days_counter_widget_photos.xml')
            .readAsStringSync();

    test('снимки внизу, а число с датой прижаты к верху — не внахлёст', () {
      final avatarRow = src.substring(src.indexOf('@+id/avatar_row'));
      expect(
        avatarRow.substring(0, avatarRow.indexOf('</LinearLayout>')),
        contains('layout_alignParentBottom="true"'),
      );
      // Колонка с числом: единственный LinearLayout без id, он держит тексты.
      final column = src.substring(src.indexOf('@+id/days_number') - 600);
      expect(column, contains('layout_alignParentTop="true"'));
    });

    test('у даты своя подложка: на тесной ячейке она встречается со снимком',
        () {
      final date = src.substring(src.indexOf('@+id/start_date'));
      expect(
        date.substring(0, date.indexOf('/>')),
        contains('background="@drawable/widget_days_date_pill"'),
      );
    });

    test('снимки мельче, чем в разметке с рисунком: над ними стоит дата', () {
      final plain =
          _f('android/app/src/main/res/layout/days_counter_widget.xml')
              .readAsStringSync();
      int avatarSize(String xml) {
        final at = xml.indexOf('@+id/avatar_left');
        final m = RegExp(r'layout_height="(\d+)dp"').firstMatch(xml.substring(at));
        return int.parse(m!.group(1)!);
      }

      expect(avatarSize(src), lessThan(avatarSize(plain)));
    });
  });
}
