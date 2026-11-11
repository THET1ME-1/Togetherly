import 'dart:ui';

import '../models/doing.dart';

/// Что кладётся в хранилище виджетов для «Чем заняты».
///
/// Виджет рисует себя сам, на Kotlin и на Swift, по этим ключам. Приложение
/// только раскладывает данные: кто чем занят, с какого времени, в какой цвет
/// покрашена половина и где лежит аватарка. Сам рисунок занятия натив находит
/// по справочнику (`doing_art_<id>`), подпись — по `doing_name_<id>`: в фоне,
/// когда запись партнёра приезжает тихим пушем, ни каталога, ни языка под
/// рукой нет.

/// Одна половина виджета.
class DoingHalf {
  const DoingHalf({required this.doing, this.wall, this.avatarPath = ''});

  final Doing doing;

  /// Цвет стены, который человек выбрал сам. `null` — цвет темы.
  final Color? wall;

  /// Файл аватарки, который видит виджет. Пусто — рисуется силуэт.
  final String avatarPath;
}

/// Покой Ту в справочнике рисунков: занятия нет или оно погасло.
const String kDoingIdle = 'idle';

String doingNameKey(String id) => 'doing_name_$id';
String doingArtKey(String id) => 'doing_art_$id';
String doingArtUrlKey(String id) => 'doing_arturl_$id';

/// Ключи пары. Половина, про которую данных нет (`null`), не пишется вовсе:
/// фон поднимают на секунды, и «не успело приехать» нельзя путать с «убрал».
Map<String, String> doingWidgetKeys({
  required String groupId,
  DoingHalf? my,
  DoingHalf? partner,
}) {
  final group = groupId.isEmpty ? 'solo' : groupId;
  final out = <String, String>{'doing_latest_group': group};

  void put(String side, DoingHalf? half) {
    if (half == null) return;
    final prefix = 'doing_${group}_$side';
    out['${prefix}_id'] = half.doing.id;
    out['${prefix}_text'] = half.doing.text;
    out['${prefix}_at'] = '${half.doing.atMs}';
    out['${prefix}_wall'] = half.wall == null ? '' : roomHex(half.wall!);
    out['${prefix}_avatar'] = half.avatarPath;
  }

  put('my', my);
  put('partner', partner);
  return out;
}
