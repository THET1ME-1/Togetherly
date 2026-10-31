import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/mascot_service.dart';

// Превью маскота на главной (блок «Нажмите для галереи») рисует Ту своим
// видом. Без отдельной ветки он проваливался в системный смайлик: у Ту нет
// ни картинки, ни ссылки каталога, рисунок приходит анимациями `cloud_*`.
void main() {
  test('превью маскота на главной знает Ту', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();
    final start = source.indexOf('class _MascotPreviewWidget');
    final end = source.indexOf('class _MascotButton');
    expect(start, greaterThanOrEqualTo(0));
    final preview = source.substring(start, end);
    expect(preview, contains('kCloudMascotId'));
    expect(preview, contains('CloudMascotView('));
  });

  test('маскота зовут Ту, а не Облачко', () {
    expect(MascotService.cloudMascot.name, isNot(contains('Облачко')));
    expect(MascotService.cloudMascot.name, anyOf('Ту', 'Tu'));
  });
}
