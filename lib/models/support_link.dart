/// Ссылка в бота поддержки с контекстом: приложение, версия, телефон, аккаунт.
///
/// Бот (служба приёмной, `togetherly-support/server/intake_rules.py`) читает
/// контекст из `/start <payload>` и не спрашивает человека о том, что уже
/// знает. Telegram пускает в payload до 64 знаков `[A-Za-z0-9_-]`, части через `_`:
///
///     <app>_<version>_<platform>_<device>_<uid>
///     tg_1-44-0-272_i_iPhone15-3_abc123def456ghi
///
/// Пустая часть — `x`. Правило зеркальное с разбором на сервере.
library;

const String supportBotName = 'TogetherlyBugsBot';

const int _payloadLimit = 64;
const int _deviceLimit = 20;

/// Платформа устройства — одной буквой, как ждёт сервер.
String _platformLetter(String platform) => switch (platform) {
      'ios' => 'i',
      'android' => 'a',
      _ => 'w',
    };

/// Всё, кроме латиницы и цифр, — в дефис; повторы схлопываются.
String _clean(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String supportStartPayload({
  required String app,
  required String version,
  required String build,
  required String platform,
  String? device,
  String? uid,
}) {
  // Версия: точки в дефисы, номер сборки четвёртым числом.
  final numbers = version.split(RegExp(r'[^0-9]+')).where((n) => n.isNotEmpty).toList();
  if (build.trim().isNotEmpty && RegExp(r'^\d+$').hasMatch(build.trim())) {
    numbers.add(build.trim());
  }
  final versionPart = numbers.isEmpty ? '0' : numbers.join('-');

  var devicePart = _clean(device ?? '');
  if (devicePart.length > _deviceLimit) {
    devicePart = devicePart.substring(0, _deviceLimit).replaceAll(RegExp(r'-+$'), '');
  }
  if (devicePart.isEmpty) devicePart = 'x';

  var uidPart = (uid ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (uidPart.length > 30) uidPart = uidPart.substring(0, 30);
  if (uidPart.isEmpty) uidPart = 'x';

  String join() => [app, versionPart, _platformLetter(platform), devicePart, uidPart].join('_');

  // Не влезает в 64 знака — сперва жертвуем uid: модель важнее для разбора,
  // а почту человек может назвать сам.
  var payload = join();
  if (payload.length > _payloadLimit) {
    uidPart = 'x';
    payload = join();
  }
  if (payload.length > _payloadLimit) {
    devicePart = 'x';
    payload = join();
  }
  return payload;
}

Uri supportBotUri(String payload) =>
    Uri.parse('https://t.me/$supportBotName?start=$payload');
