/// В какой валюте показывать и просить цену Togetherly+.
///
/// В lava.top у товара три цены — рубли, доллары, евро, — и до 24.08.2026
/// приложение всегда просило рубли: человек из Германии видел рублёвую сумму и
/// платил рублями, хотя цена в евро у товара есть. Магазины Apple и Google
/// решают это сами (у них своя цена в каждой стране), поэтому правило нужно
/// только там, где оплата идёт счётом lava.
///
/// Регион берётся у устройства, а не у языка интерфейса: человек с русским
/// языком в Берлине платит евро, а не рублями.
library;

/// Валюты, которые понимает lava.top.
const String kCurrencyRub = 'RUB';
const String kCurrencyUsd = 'USD';
const String kCurrencyEur = 'EUR';

/// Страны, где цена идёт в рублях: рубль там ходит наравне с местной валютой,
/// а СБП — единственный работающий способ оплаты (карточная форма lava
/// российские карты не принимает).
const Set<String> _rubleCountries = {'RU', 'BY', 'KZ', 'KG', 'AM', 'TJ', 'UZ'};

/// Еврозона плюс страны, где евро привычнее доллара.
const Set<String> _euroCountries = {
  'AT', 'BE', 'BG', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FR',
  'GB', 'GR', 'HR', 'HU', 'IE', 'IS', 'IT', 'LT', 'LU', 'LV', 'MT', 'NL',
  'NO', 'PL', 'PT', 'RO', 'RS', 'SE', 'SI', 'SK', 'UA', 'GE', 'MD', 'ME',
  'AL', 'BA', 'MK', 'TR',
};

/// Валюта по коду страны устройства. Незнакомая страна платит долларами —
/// это валюта по умолчанию у самой lava.
///
/// [country] — двухбуквенный код (`RU`, `DE`); пусто или мусор → доллары.
String currencyForCountry(String? country) {
  final code = (country ?? '').trim().toUpperCase();
  if (code.length != 2) return kCurrencyUsd;
  if (_rubleCountries.contains(code)) return kCurrencyRub;
  if (_euroCountries.contains(code)) return kCurrencyEur;
  return kCurrencyUsd;
}

/// Чем платить в этой валюте.
///
/// За рубли — СБП: карточная форма lava российские карты не принимает, и
/// единственные живые оплаты прошли именно по СБП. В остальных валютах
/// провайдера выбирает сама lava, поэтому способ не навязываем.
String paymentMethodFor(String currency) =>
    currency == kCurrencyRub ? 'sbp' : '';
