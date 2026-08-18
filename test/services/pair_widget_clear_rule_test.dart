// Когда виджет пары действительно надо стирать.
//
// 18.08.2026 в сборке 1.29.2+203 у тестера пропали имена и настроения на
// рабочем столе, хотя на сервере они лежали. Причина: накануне я повесил
// очистку контейнера на `unbindFromGroup`, считая, что отвязка — это распад
// пары. На деле экран зовёт её и при обычном переключении: у человека две
// связи, и при смене активной сперва отвязка, следом привязка. Очистка успевала
// затереть тексты, а гонка с синхронизацией оставляла кашу — часть путей пуста,
// часть на месте (ровно это в отчётах за 10:50 и 11:05).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  test('пара распалась — стираем', () {
    expect(shouldClearPairWidget(wasPaired: true, isPaired: false), isTrue);
  });

  test('переключились на другую связь — не трогаем', () {
    expect(shouldClearPairWidget(wasPaired: true, isPaired: true), isFalse,
        reason: 'иначе виджет пустеет при каждой смене активной пары');
  });

  test('пара только собралась — не трогаем', () {
    expect(shouldClearPairWidget(wasPaired: false, isPaired: true), isFalse);
  });

  test('пары не было и нет — стирать нечего', () {
    expect(shouldClearPairWidget(wasPaired: false, isPaired: false), isFalse);
  });
}
