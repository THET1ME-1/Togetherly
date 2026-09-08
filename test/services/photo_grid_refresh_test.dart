// Сетку фото обновляет не только экран виджетов.
//
// `refreshPhotoGrid` до 08.09.2026 звали из трёх мест, и все три — внутри
// `widget_screen`: при постановке виджета и при изменении данных партнёра, пока
// экран открыт. Ни общая синхронизация службы, ни фоновое обновление сетку не
// трогали. Итог на рабочем столе: человек поставил «Сетку фото», партнёр
// поменял снимки, а сетка стоит пустой, пока в приложение не зайдут именно на
// вкладку виджетов. Проверено на эмуляторе: запись четырёх снимков партнёру не
// меняла ничего до открытия экрана — и наполнялась за секунды после.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('сетку зовут из общей синхронизации и из фона', () {
    final service = File('lib/services/widget_service.dart').readAsStringSync();
    final home =
        File('lib/services/home_widget_service.dart').readAsStringSync();

    expect(service.contains('refreshPhotoGrid'), isTrue,
        reason: 'служба обязана обновлять сетку своим проходом');

    // В фоне — внутри refreshLoveWidgetFromServer, а не только на экране.
    final bg = home.indexOf('Future<void> refreshLoveWidgetFromServer');
    expect(bg, greaterThan(-1));
    final bgBody = home.substring(bg, bg + 8000);
    expect(bgBody.contains('refreshPhotoGrid'), isTrue,
        reason: 'фоновое обновление тоже должно наполнять сетку');
  });
}
