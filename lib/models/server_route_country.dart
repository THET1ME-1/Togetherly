import 'dart:ui' show Locale;

/// Часовые пояса Украины, старые и новые имена. Крыма (`Europe/Simferopol`)
/// тут нет: там российские сети, и сервер доступен напрямую.
const _ukraineZones = {
  'Europe/Kyiv',
  'Europe/Kiev',
  'Europe/Uzhgorod',
  'Europe/Zaporozhye',
};

/// Часовые пояса США. Вложенные (`America/Indiana/…` и подобные) и старые
/// `US/…` ловят префиксы ниже.
const _usZones = {
  'America/New_York',
  'America/Detroit',
  'America/Chicago',
  'America/Menominee',
  'America/Denver',
  'America/Boise',
  'America/Phoenix',
  'America/Los_Angeles',
  'America/Anchorage',
  'America/Juneau',
  'America/Sitka',
  'America/Metlakatla',
  'America/Yakutat',
  'America/Nome',
  'America/Adak',
  'Pacific/Honolulu',
  'America/Indianapolis',
  'America/Louisville',
  'America/Fort_Wayne',
  'America/Shiprock',
  'Navajo',
};
const _usZonePrefixes = [
  'US/',
  'America/Indiana/',
  'America/Kentucky/',
  'America/North_Dakota/',
];

/// Нужен ли телефону обход для Украины (`ServerRoute`, 24.10.2026).
///
/// В 1.39 обход стоял у всех, и мгновенная связь не поднималась ни у кого:
/// телефон получал пропуск Centrifugo, а сокет через обход до сервера не
/// доходил (замер 24.10.2026: 0 из 536 человек на 1.39 на связи против 46% на
/// 1.38). Теперь обход включается только там, где сервер режут провайдеры:
/// Украина и США.
///
/// Главное — часовой пояс телефона по имени города ([timeZone]): он не
/// зависит от языка, и украинец с телефоном на «Русском (Россия)» узнаётся
/// так же, как с украинским. Пояс не узнали (нет ответа системы) — решают
/// язык и регион системы вместе со сдвигом от UTC: телефон на английском
/// (США) в Москве — не американский, украинец в Канаде до сервера и так
/// доходит.
bool serverRouteWanted(
  List<Locale> locales,
  Duration utcOffset, {
  String? timeZone,
}) {
  final zone = timeZone?.trim() ?? '';
  if (zone.isNotEmpty) {
    return _ukraineZones.contains(zone) ||
        _usZones.contains(zone) ||
        _usZonePrefixes.any(zone.startsWith);
  }

  if (locales.isEmpty) return false;
  final hours = utcOffset.inMinutes / 60;

  // Украина: зимой UTC+2, летом UTC+3. Язык или регион — у любого из языков
  // системы: многие ставят русский интерфейс, а украинский держат вторым.
  final ukrainian = locales.any((locale) =>
      locale.languageCode.toLowerCase() == 'uk' ||
      locale.countryCode?.toUpperCase() == 'UA');
  if (ukrainian && hours >= 2 && hours <= 3) return true;

  // США: от Гавайев (UTC−10) до восточного побережья летом (UTC−4). Только
  // первый язык: английский (США) стоит вторым у многих и вне Америки.
  final american = locales.first.countryCode?.toUpperCase() == 'US';
  return american && hours >= -10 && hours <= -4;
}
