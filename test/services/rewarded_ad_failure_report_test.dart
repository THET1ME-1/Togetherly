// Причина, по которой ролик не загрузился, доходит до Bugsink.
//
// Обращение 210 (30.09.2026): «реклама не грузится третий день», человек
// проверил VPN, DNS и экономию трафика. Код ошибки Яндекса уходил только в
// debugPrint, и ответить было нечем.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/services/rewarded_ad_service.dart').readAsStringSync();

  test('каждая неудача загрузки сообщает код ошибки', () {
    final failed = src.substring(src.indexOf('onAdFailedToLoad: (error)'));
    expect(failed.substring(0, 400), contains("_reportLoadFailure('\${error.code}'"));
    expect(src, contains("_reportLoadFailure('exception', '\$e')"));
  });

  test('событие одно за запуск и несёт код ошибки', () {
    expect(src, contains('_loadFailureReported'));
    expect(src, contains("s.setTag('ad_error_code', code)"));
    expect(src, contains("'Yandex rewarded never loaded'"));
  });
}
