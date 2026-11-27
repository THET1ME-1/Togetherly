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

/// Ключи своей половины, которые читает [myHalfFromWidgetKeys].
List<String> myHalfKeys(String groupId) {
  final prefix = 'doing_${groupId.isEmpty ? 'solo' : groupId}_my';
  return ['${prefix}_id', '${prefix}_text', '${prefix}_at', '${prefix}_wall'];
}

/// Своя половина такой, какой её сейчас рисует виджет. Обратное к
/// [doingWidgetKeys]: лист выбора по нажатию на виджет открывается сразу с
/// тем, что человек видит на рабочем столе, а не ждёт сервер. Ключей нет —
/// `null`. [read] отдаёт значение ключа или `null`.
({Doing doing, Color? wall})? myHalfFromWidgetKeys(String groupId, String? Function(String key) read) {
  final keys = myHalfKeys(groupId);
  final id = read(keys[0]);
  if (id == null) return null;
  final at = int.tryParse(read(keys[2]) ?? '') ?? 0;
  final doing = Doing.fromData({
    'doing': {'id': id, 'text': read(keys[1]) ?? '', 'at': at},
  });
  return (doing: doing, wall: roomColorOf({'room': read(keys[3]) ?? ''}));
}
