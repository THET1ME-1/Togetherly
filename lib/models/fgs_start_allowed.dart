/// Можно ли прямо сейчас поднимать location-сервис переднего плана.
///
/// Android 12+ запрещает старт foreground-сервиса типа `location` из фона:
/// `geolocator` поднимает такой сервис внутри `getPositionStream`, и запрет
/// прилетает `ForegroundServiceStartNotAllowedException` — мимо try/catch и
/// мимо `onError` потока. Перехватить нечем, единственная защита — не звать.
///
/// За неделю так упало у 49 человек. Прежняя проверка считала передним планом
/// и НЕИЗВЕСТНОЕ состояние (`lifecycleState == null`), а это ровно холодный
/// старт из фонового пробуждения — тихий пуш, WorkManager, обновление виджета.
library;

import 'package:flutter/widgets.dart';

/// [state] — состояние приложения (`WidgetsBinding.instance.lifecycleState`),
/// `null` означает «первый кадр ещё не был». [android] — нужна ли проверка
/// вообще: на iPhone фоновая геопозиция разрешена режимом в `Info.plist`.
bool fgsLocationStartAllowed(AppLifecycleState? state, {required bool android}) {
  if (!android) return true;
  return state == AppLifecycleState.resumed ||
      // Шторка уведомлений и входящий звонок дают inactive, но приложение
      // остаётся на экране — это не фон.
      state == AppLifecycleState.inactive;
}
