/// Кому сейчас принадлежат данные виджетов на этом устройстве.
///
/// Хранилище виджетов общее для телефона: и `HomeWidgetPreferences` на Android,
/// и контейнер App Group на iOS живут отдельно от аккаунта. Поэтому смену
/// человека надо ловить самим — иначе на столе остаётся пара из прошлой жизни.
///
/// Проверка была одна, в `main()`, и срабатывала только на холодном старте:
/// выход и вход в другой аккаунт внутри живого приложения проходили мимо неё
/// (жалоба 18.08.2026). Теперь решение принимается на каждое изменение сессии,
/// а правило вынесено сюда — оно должно быть проверяемым без телефона.
library;

enum WidgetOwnerAction {
  /// Тот же человек: обновление токена шлёт это событие по нескольку раз.
  none,

  /// Владельца ещё не записывали — запоминаем, но данные не трогаем.
  remember,

  /// Пришёл другой человек: стираем прошлое и запоминаем нового.
  wipeAndRemember,

  /// Вышли из аккаунта: стираем и забываем владельца.
  wipeAndForget,
}

WidgetOwnerAction widgetOwnerAction({
  required String? previous,
  required String current,
}) {
  if (current.isEmpty) return WidgetOwnerAction.wipeAndForget;
  if (previous == null || previous.isEmpty) return WidgetOwnerAction.remember;
  if (previous == current) return WidgetOwnerAction.none;
  return WidgetOwnerAction.wipeAndRemember;
}
