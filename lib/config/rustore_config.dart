/// Конфигурация RuStore Billing.
///
/// Используется только в сборке для RuStore (`--dart-define=STORE=rustore`).
/// В сборке для Google Play / App Store эти значения не читаются.
abstract final class RuStoreConfig {
  /// ID приложения из RuStore Консоли (Приложение → Основная информация →
  /// «ID приложения»). ⚠️ ЗАМЕНИТЬ перед сборкой rustore-флейвора.
  static const String appId = 'РАЗМЕР_ЗАМЕНИ_RUSTORE_APP_ID';

  /// Deeplink-схема для возврата из платёжного флоу RuStore. Должна быть
  /// объявлена в AndroidManifest (см. docs/RUSTORE.md). Уникальна для приложения.
  static const String deeplinkScheme = 'togetherlyrustore';

  /// Сконфигурирован ли RuStore (appId подставлен). Защита от запуска платежей
  /// с placeholder-значением.
  static bool get isConfigured =>
      appId.isNotEmpty && !appId.contains('ЗАМЕНИ');
}
