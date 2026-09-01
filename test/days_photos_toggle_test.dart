// Тумблер «Наши фото вместо рисунка» на виджете «Дни вместе».
//
// Жалоба 01.09.2026: «Функция замены на аватарки не работает. В результате
// обыкновенный виджет появляется + переключатель перестаёт работать и
// отключаться». На снимке экрана тумблер стоит «включено», а превью и виджет
// рисуют пару-картинку.
//
// Ломалось так: сервис писал в настройки ПРОСЬБУ («включить»), а фото на
// виджете появлялись только если обе аватарки успели скачаться. Не скачались —
// на столе рисунок, в приложении «включено», и вернуть тумблер нечем.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_photo_cache.dart';

void main() {
  group('daysPhotosApplied', () {
    test('обе аватарки на диске — фото включаются', () {
      expect(
        daysPhotosApplied(
          requested: true,
          myPath: '/data/widget_days_avatar_my.jpg',
          partnerPath: '/data/widget_days_avatar_partner.jpg',
        ),
        isTrue,
      );
    });

    test('аватарка партнёра не скачалась — остаётся рисунок', () {
      expect(
        daysPhotosApplied(
          requested: true,
          myPath: '/data/widget_days_avatar_my.jpg',
          partnerPath: '',
        ),
        isFalse,
      );
    });

    test('выключено — фото не показываем даже с файлами', () {
      expect(
        daysPhotosApplied(
          requested: false,
          myPath: '/data/my.jpg',
          partnerPath: '/data/partner.jpg',
        ),
        isFalse,
      );
    });
  });

  group('Состояние тумблера — по факту, а не по просьбе', () {
    test('в настройки уходит usePhotos, ответ возвращается экрану', () {
      final src =
          File('lib/services/home_widget_service.dart').readAsStringSync();
      final start = src.indexOf('Future<bool> setDaysCounterPhotos(');
      expect(start, greaterThan(0),
          reason: 'метод должен отвечать, что вышло на самом деле');
      final body = src.substring(start, start + 3000);
      expect(body.contains('prefs.setBool(_daysPhotosKeyFor(groupId), usePhotos)'),
          isTrue,
          reason: 'запоминаем факт, иначе тумблер обещает несуществующие фото');
      expect(body.contains('prefs.setBool(_daysPhotosEnabledKey, enabled)'),
          isFalse,
          reason: 'просьбу в настройки писать нельзя — это и был баг');
      expect(body.contains('return usePhotos;'), isTrue);
    });

    test('экран возвращает тумблер в исходное, когда фото не вышли', () {
      final src = File('lib/screens/widget_screen.dart').readAsStringSync();
      final start = src.indexOf('Future<void> _setDaysPhotos(');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 1200);
      expect(body.contains('_daysPhotosEnabled = applied'), isTrue);
      expect(body.contains('daysPhotosFailed'), isTrue,
          reason: 'человеку надо сказать, почему на виджете остался рисунок');
    });
  });
}
