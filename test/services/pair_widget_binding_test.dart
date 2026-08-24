// Привязка виджета к паре обязана дописываться при каждой синхронизации.
//
// Отчёты `widget-diag` за 23.08.2026 (600 отчётов с iPhone): у 19 устройств
// `love_widget_group_id` пуст, а `my_name` и `partner_name` записаны. Виджет в
// такой связке рисует «Подключите партнёра» при живой паре — жалоба
// saxkshaser со снимком рабочего стола, 23.08.2026.
//
// Очистка тут ни при чём: `clearPairWidgetData` стирает имена вместе с
// привязкой, а они на месте. Привязку писал ровно один вызов — `bindToGroup`,
// и он выходит первой строкой, когда группа та же. Значит промах записи (на
// iOS `home_widget` отвечает ошибкой, пока не задан App Group) починить было
// уже нечем: имена продолжали обновляться своим путём, привязка оставалась
// пустой до смены пары.
//
// Поэтому привязка уехала в общую полезную нагрузку синхронизации: она идёт с
// каждым обновлением данных, и промах лечится сам собой.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  group('привязка виджета к паре', () {
    test('оба ключа уходят, когда пара известна', () {
      final out = pairBindingPayload(groupId: 'g123', partnerUid: 'u456');
      expect(out['love_widget_group_id'], 'g123');
      expect(out['love_widget_partner_uid'], 'u456');
    });

    test('пустую группу не пишем: это стёрло бы живую привязку', () {
      expect(pairBindingPayload(groupId: '', partnerUid: 'u456'), isEmpty,
          reason: 'распад пары чистит clearPairWidgetData, а не синхронизация');
    });

    test('партнёр без uid оставляет прежнее значение ключа', () {
      final out = pairBindingPayload(groupId: 'g123', partnerUid: '');
      expect(out, {'love_widget_group_id': 'g123'},
          reason: 'подписка на партнёра поднимается позже привязки к группе');
    });
  });

  test('синхронизация виджета дописывает привязку', () {
    final src =
        File('lib/services/widget_service.dart').readAsStringSync();
    final sync = src.substring(src.indexOf('_syncToNativeWidget() async'));
    expect(
      sync.contains('pairBindingPayload'),
      isTrue,
      reason: 'иначе промах записи в bindToGroup останется навсегда: '
          'при той же группе она выходит первой строкой',
    );
  });
}
