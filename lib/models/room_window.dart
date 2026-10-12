/// Каким окном открывать комнату совместного просмотра на iPhone.
///
/// Встроенная комната — это браузер внутри экрана Flutter: каждое касание
/// сначала спрашивает у Flutter, чьё оно, и только потом уходит странице. На
/// iPhone у каждого четвёртого оно до страницы не доходило вовсе (замер
/// 06–11.10.2026: 430 заходов из 1331 без касаний, на Android 8%), и три
/// правки этого механизма долю не сдвинули. Нативное окно — тот же браузер, но
/// своим экраном поверх приложения: Flutter на пути пальца нет, как в Safari,
/// где у людей всё работает.
///
/// Долю людей с нативным окном задаёт сервер (`app_config.room_native_ios`,
/// проценты). Так окно сравнивается со встроенным на живых людях — страница
/// получает метку `nb=1` и замер касаний делится по ней — и выключается без
/// релиза.
library;

/// Разбирает поле `room_native_ios`: проценты 0…100. Всё непонятное — ноль,
/// то есть прежнее встроенное окно.
int roomNativeShare(Object? raw) {
  if (raw is bool) return raw ? 100 : 0;
  num? value;
  if (raw is num) value = raw;
  if (raw is String) value = num.tryParse(raw.trim());
  if (value == null || value.isNaN) return 0;
  return value.clamp(0, 100).toInt();
}

/// Корзина человека, 0…99. Считается из его id, поэтому не меняется от
/// запуска к запуску: в замере человек остаётся в своей группе.
///
/// FNV-1a вручную: `String.hashCode` между запусками не обязан совпадать.
int roomBucket(String uid) {
  var hash = 0x811c9dc5;
  for (final unit in uid.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash % 100;
}

/// Открывать ли комнату нативным окном.
///
/// Только iPhone и только сама комната: у ленты вдвоём своя страница и
/// скрытая лента площадки рядом. Без входа корзины нет, и окно достаётся
/// лишь при полной доле.
bool roomOpensNatively({
  required bool ios,
  required bool reels,
  required int share,
  required String uid,
}) {
  if (!ios || reels || share <= 0) return false;
  if (share >= 100) return true;
  if (uid.isEmpty) return false;
  return roomBucket(uid) < share;
}
