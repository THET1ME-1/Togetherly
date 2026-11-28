import '../utils/pair_time.dart';

/// Время партнёра (TOG-48, 14.11.2026).
///
/// Отзыв в Google Play: «чтобы можно было отслеживать часовой пояс / реальное
/// время партнёра». Пояс каждый телефон кладёт в своё поле `data` записи
/// `widget_data` ключом `zone` (строка `±HH:MM`, как `tz` у настроений): схему
/// сервера менять не нужно, правка записи и так доходит до партнёра.

/// Ключ пояса в поле `data`.
const String kZoneKey = 'zone';

/// Пояс из поля `data` записи виджета. Пусто и мусор — null.
String? zoneFromData(dynamic data) {
  if (data is! Map) return null;
  final raw = data[kZoneKey];
  if (raw is! String) return null;
  return PairTime.zoneToDuration(raw) == null ? null : raw;
}

/// Ключ имени пояса (`Europe/Kyiv`) в поле `data`. Смещения хватает часам
/// партнёра, а серверу, который шлёт напоминания «Наших дат» в 9:00 по часам
/// человека (TOG-61), нужно имя: по нему он знает переводы часов.
const String kZoneNameKey = 'tzn';

/// Имя пояса из поля `data` записи виджета. Пусто и мусор — null.
String? zoneNameFromData(dynamic data) {
  if (data is! Map) return null;
  final raw = data[kZoneNameKey];
  return raw is String && raw.isNotEmpty ? raw : null;
}

/// Поле `data` с новым поясом и, если телефон его назвал, именем пояса.
/// Остальные ключи (занятие, заметка, цвет) на месте: сервер перезаписывает
/// json целиком.
Map<String, dynamic> withZone(Map<dynamic, dynamic> data, String zone, {String? name}) => {
      for (final e in data.entries) e.key.toString(): e.value,
      kZoneKey: zone,
      if (name != null && name.isNotEmpty) kZoneNameKey: name,
    };

/// Ключ подписи «у неё 02:14» по роду партнёра.
String partnerClockKey(String gender) => switch (gender) {
      'female' => 'chatPartnerClockF',
      'male' => 'chatPartnerClockM',
      _ => 'chatPartnerClockX',
    };

/// Часы партнёра `HH:MM`, если его пояс отличается от моего. В одном поясе
/// подпись не нужна: время у обоих одно и то же.
String? partnerClock(String? partnerZone, {DateTime? now}) {
  final offset = PairTime.zoneToDuration(partnerZone);
  if (offset == null) return null;
  final moment = now ?? DateTime.now();
  if (offset == moment.timeZoneOffset) return null;
  final there = moment.toUtc().add(offset);
  return '${there.hour.toString().padLeft(2, '0')}:${there.minute.toString().padLeft(2, '0')}';
}
