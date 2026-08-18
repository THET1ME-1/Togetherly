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

import 'dart:convert';

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


/// Кто в сессии по событию `authStore.onChange`.
///
/// Пустая строка — выход. `null` — «не знаю»: трогать данные виджетов нельзя.
///
/// Разбирать событие по `record?.id` нельзя: запись бывает пустой при живом
/// токене — это «полумёртвая сессия», давняя болезнь iOS, из-за которой уже
/// терялись воспоминания (см. фолбэк в `PocketBaseService.userId`). 18.08.2026
/// на этом же стёрлись виджеты у тестера: пустой id прочитался как выход.
String? sessionUidOf({required String token, required String? recordId}) {
  if (token.isEmpty) return '';
  if (recordId != null && recordId.isNotEmpty) return recordId;
  return _uidFromToken(token);
}

String? _uidFromToken(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(
      utf8.decode(base64Decode(base64.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final id = payload['id'];
    return (id is String && id.isNotEmpty) ? id : null;
  } catch (_) {
    return null;
  }
}
