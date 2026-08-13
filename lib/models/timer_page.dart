/// Какую страницу карусели таймеров показывать на главной.
///
/// Страница выбиралась один раз, в `initState`, по основному таймеру. Но
/// таймеры приезжают позже первого кадра: на старте список пуст, карусель
/// встаёт на нулевую страницу и там и остаётся — обновление списка её больше
/// не трогало. Человек каждый раз доматывал до своего таймера рукой (жалоба со
/// скриншотом 13 августа 2026).
///
/// Теперь страница пересчитывается при каждом обновлении списка, пока человек
/// не листнул сам: его свайп важнее любого умолчания.
int timerPageFor({
  required List<String> ids,
  required String? defaultId,
  required int current,
  required bool userSwiped,
}) {
  if (ids.isEmpty) return 0;
  final last = ids.length - 1;
  final safeCurrent = current.clamp(0, last);
  if (userSwiped) return safeCurrent;
  final wanted = defaultId == null ? -1 : ids.indexOf(defaultId);
  return wanted >= 0 ? wanted : safeCurrent;
}
