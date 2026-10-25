import 'dart:ui' show Locale;

/// Нужен ли телефону обход для Украины (`ServerRoute`, 24.10.2026).
///
/// В 1.39 обход стоял у всех, и мгновенная связь не поднималась ни у кого:
/// телефон получал пропуск Centrifugo, а сокет через обход до сервера не
/// доходил (замер 24.10.2026: 0 из 536 человек на 1.39 на связи против 46% на
/// 1.38). Теперь обход включается только там, где сервер режут провайдеры:
/// Украина и США.
///
/// Страна берётся, как язык, из языка и региона системы, а часовой пояс
/// отсекает ложные совпадения: телефон на английском (США) в Москве —
/// не американский, украинец в Канаде до сервера и так доходит.
bool serverRouteWanted(List<Locale> locales, Duration utcOffset) {
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
