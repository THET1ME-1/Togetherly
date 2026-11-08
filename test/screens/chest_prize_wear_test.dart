import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/services/tu_wear_service.dart';

// Владелец, 08.11.2026: «Вещи огромные и не анимированные, если нажать из
// сундука». Экран приза рисовал значок вещи — неподвижную картинку для
// плитки гардероба, обрезанную по самой вещи, — в 1,3 ширины экрана: плед,
// зонт и листопад вылезали за края. Теперь на экране приза живой Ту в этой
// вещи, как в гардеробе, даже если её ещё не выиграли (примерка).
void main() {
  Map<String, dynamic> row(String key, String cat) => {
        'id': 'wear_$key',
        'kind': 'wear',
        'name_ru': key,
        'name_en': key,
        'sort': 500,
        'data': {
          'key': key,
          'cat': cat,
          'src': 'chest',
          'set': 'autumn',
          'rarity': 'rare',
          'icon': 'tuw_${key}_icon',
          'layers': {
            'idle_base': ['tuw_${key}_idle_base_b', 'tuw_${key}_idle_base_f'],
          },
        },
      };

  test('примерка показывает слои вещи, которой у человека нет', () {
    CatalogService.instance.debugApply([row('blanket', 'neck')]);
    TuWearService.instance.debugSet(outfit: const {}, granted: const {});
    final tried = TuWearService.instance.layersFor(art: 'cloud_idle_base', tryOn: const {'neck': 'blanket'});
    expect(tried.back, ['tuw_blanket_idle_base_b']);
    expect(tried.front, ['tuw_blanket_idle_base_f']);
    final worn = TuWearService.instance.layersFor(art: 'cloud_idle_base');
    expect(worn.front, isEmpty, reason: 'без примерки — только надетое');
  });

  test('экран приза показывает вещь на живом Ту, а не значок', () {
    final src = File('lib/screens/chest_prize_screen.dart').readAsStringSync();
    expect(src, contains('CloudMascotView('));
    expect(src, contains('tryOn:'));
  });
}
