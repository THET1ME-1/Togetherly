// Будить Dart на Android из виджета и тихого пуша можно только разовой задачей
// пакета workmanager. Путь home_widget (HomeWidgetBackgroundIntent) на Android
// мёртв: обработчик интерактивности там намеренно не регистрируется
// (main.dart), задача падает с «No callbackHandle saved», а плагин ставит их
// цепочкой APPEND — после первого падения WorkManager проваливает каждую
// следующую, не запуская. Поймано на эмуляторе 19.09.2026: карта «Где мы» не
// перерисовывалась ни по пушу, ни по смене ячейки, а в базе WorkManager лежала
// цепочка из пяти FAILED.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _kt(String name) =>
    File('android/app/src/main/kotlin/com/togetherly/love/$name').readAsStringSync();

void main() {
  final wake = _kt('WidgetRefreshWake.kt');
  final fcm = _kt('FcmService.kt');
  final map = _kt('PairMapWidgetProvider.kt');
  final dispatcher =
      File('lib/services/widget_background_refresh_service.dart').readAsStringSync();

  test('тихий пуш и виджет карты не зовут HomeWidgetBackgroundIntent', () {
    expect(fcm, isNot(contains('HomeWidgetBackgroundIntent')));
    expect(map, isNot(contains('HomeWidgetBackgroundIntent')));
    expect(fcm, contains('WidgetRefreshWake.enqueue('));
    expect(map, contains('WidgetRefreshWake.enqueue('));
    expect(map, contains('WidgetRefreshWake.TASK_MAP'));
  });

  test('разовая задача не отравляется прошлым падением', () {
    expect(wake, contains('ExistingWorkPolicy.APPEND_OR_REPLACE'));
    expect(wake, isNot(contains('ExistingWorkPolicy.APPEND,')));
    expect(wake, contains('BackgroundWorker.DART_TASK_KEY'));
  });

  test('имена задач совпадают в Kotlin и в диспетчере Dart', () {
    final names = RegExp(r'const val TASK_\w+ = "(\w+)"')
        .allMatches(wake)
        .map((m) => m.group(1)!)
        .toList();
    expect(names, containsAll(['widgetRefresh', 'mapWidget']));
    for (final n in names) {
      expect(dispatcher, contains("'$n'"), reason: 'диспетчер не знает задачу $n');
    }
    expect(dispatcher, contains('PairMapWidgetService.instance.refreshInBackground'));
  });
}
