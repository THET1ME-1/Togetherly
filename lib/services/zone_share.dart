import 'package:flutter/foundation.dart';

import '../models/partner_clock.dart';
import '../utils/pair_time.dart';
import 'device_time_zone.dart';
import 'pb_data_service.dart';
import 'pocketbase_service.dart';

/// Кладёт свой пояс в поле `data` своей записи виджета, чтобы партнёр видел
/// моё время (TOG-48). Пишет только при смене пояса: перелёт, переход на
/// летнее время, первая сборка с этой службой.
class ZoneShare {
  ZoneShare._();

  /// Какой пояс уже лежит в записи пары — повторно не пишем.
  static final Map<String, String> _sent = {};

  static Future<void> sync(String groupId) async {
    if (groupId.isEmpty || groupId == 'solo') return;
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return;
    final zone = PairTime.zoneNow();
    // Имя пояса (`Europe/Kyiv`) нужно серверу для напоминаний «Наших дат».
    final name = await deviceTimeZone();
    final mark = '$zone|${name ?? ''}';
    if (_sent[groupId] == mark) return;

    try {
      // Своё `data` читаем целиком: в нём живут занятие, заметка и цвет
      // комнатки, а запись перезаписывает поле json целиком.
      final existing = await PbDataService().loadWidgetOrThrow(groupId, uid);
      final raw = existing?.data['data'];
      if (zoneFromData(raw) == zone && (name == null || zoneNameFromData(raw) == name)) {
        _sent[groupId] = mark;
        return;
      }
      final data = withZone(raw is Map ? raw : const {}, zone, name: name);
      if (await PbDataService().upsertWidget(groupId, uid, {'data': data})) {
        _sent[groupId] = mark;
      }
    } catch (e) {
      debugPrint('ZoneShare: пояс не сохранился — $e');
    }
  }
}
