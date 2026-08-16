import '../services/app_icon_service.dart';

/// Починка иконок приложения: на рабочем столе должен быть ровно один ярлык.
///
/// Android хранит состояние каждого `activity-alias` отдельно от манифеста.
/// Выбранную иконку приложение включает явно, и это переживает обновление —
/// а новый `.IconDefault` приехал включённым из манифеста. Итог: включённых
/// два, лаунчер рисует два ярлыка («обновил, стало два», 16.08.2026).
///
/// Правило нарочно бережное: выбор человека важнее нового умолчания. Отнять
/// цветную иконку у того, кто её ставил, — это вторая жалоба вместо первой.

/// Нужен ли ремонт: здоровое состояние — ровно один включённый alias.
bool appIconNeedsRepair(List<String> enabled) => enabled.length != 1;

/// Какой alias оставить включённым.
///
/// [enabled] — что система считает включённым сейчас, [saved] — выбор из
/// настроек приложения (может отсутствовать у тех, кто ставил иконку старой
/// сборкой). Незнакомому значению не верим: alias с таким именем в манифесте
/// может не существовать, и ярлык пропадёт совсем.
String appIconToKeep({required List<String> enabled, String? saved}) {
  bool known(String? id) =>
      id != null && AppIconService.options.any((o) => o.id == id);

  if (known(saved)) return saved!;

  // Явно включённая цветная — след ручного выбора, сделанного до того, как
  // приложение стало записывать его в настройки.
  final chosen = enabled.where((id) => id != AppIconService.defaultId);
  if (chosen.isNotEmpty && known(chosen.first)) return chosen.first;

  return AppIconService.defaultId;
}
