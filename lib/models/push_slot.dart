/// Место уведомления в шторке: Android различает уведомления по паре
/// (метка, номер), и новое на том же месте заменяет прежнее.
class PushSlot {
  const PushSlot(this.id, this.tag);

  final int id;
  final String? tag;
}

/// Куда положить своё уведомление о партнёре.
///
/// Сообщение партнёра доходит двумя путями: сокет приложения поднимает своё
/// уведомление, а сервер, не видя человека на связи, шлёт пуш FCM с меткой
/// вида события (`chat`, `mood`, `miss`, `memory`, `gift`), и баннер такого
/// пуша система кладёт на место (метка, 0). Своё уведомление на Android
/// встаёт туда же: дошли оба — в шторке одна строка, а не две (обращение
/// 25.11.2026). Без вида события и на iPhone, где пуш при открытом приложении
/// не приходит, место прежнее — [ownId] без метки.
PushSlot pushSlot({
  required String? thread,
  required int ownId,
  required bool android,
}) {
  if (android && thread != null && thread.isNotEmpty) return PushSlot(0, thread);
  return PushSlot(ownId, null);
}
