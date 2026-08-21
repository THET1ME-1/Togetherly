/// Ссылка, пришедшая системным каналом маршрутов.
///
/// На iPhone приложение живёт на сценах (`FlutterSceneDelegate`), и при
/// запуске по ссылке система кладёт её в `scene:willConnectTo:`, а не в
/// `launchOptions` делегата приложения. Плагин `app_links` читает как раз
/// `launchOptions`, поэтому на холодном старте ссылка до него не доходит —
/// тап по виджету с закрытого приложения не делал ничего. Flutter в этом
/// случае толкает ссылку в канал `flutter/navigation`, и подобрать её можно
/// только там.
library;

/// Наши ссылки: всё, что начинается с `loveapp://`.
const String kAppLinkScheme = 'loveapp';

/// Достаёт нашу ссылку из аргументов канала маршрутов.
///
/// `pushRoute` присылает строку, `pushRouteInformation` — карту с `location`.
/// Обычные маршруты приложения (`/`, `/home`) и чужие схемы возвращают null:
/// их разбирают те, кому положено.
Uri? uriFromRoute(Object? arguments) {
  final raw = arguments is Map ? arguments['location'] : arguments;
  if (raw is! String || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != kAppLinkScheme) return null;
  return uri;
}
