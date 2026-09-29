/// Досмотренный ролик, за который сундук ещё не открылся.
///
/// Раньше номер такого открытия жил только в памяти экрана: ушёл человек с
/// экрана, пока висело «Открываем…», или приложение выгрузили — и ролик
/// пропадал, следующее открытие просило новый (обращение 211, 29.09.2026).
/// Теперь номер лежит на диске, пока сервер не ответит, и открытие доходит
/// без новой рекламы. Сервер по тому же номеру второй раз не разыгрывает: если
/// приз уже выпал, он отдаёт его же.
class ChestPending {
  const ChestPending({required this.openId, required this.fromJar, required this.at});

  final String openId;
  final bool fromJar;
  final DateTime at;

  /// Сколько держим недоделанное открытие. Дольше — человек давно забыл, а
  /// приз по старому номеру всё равно ляжет в сегодняшний лимит.
  static const Duration keep = Duration(days: 3);

  static final RegExp _id = RegExp(r'^[a-z0-9]{15}$');

  Map<String, Object> toJson() => {'id': openId, 'jar': fromJar, 'at': at.millisecondsSinceEpoch};

  /// null — записи нет, она кривая или протухла.
  static ChestPending? fromJson(Object? raw, {required DateTime now}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final at = raw['at'];
    if (id is! String || !_id.hasMatch(id) || at is! int) return null;
    final when = DateTime.fromMillisecondsSinceEpoch(at);
    final age = now.difference(when);
    if (age.isNegative && age.abs() > const Duration(minutes: 5)) return null;
    if (age > keep) return null;
    return ChestPending(openId: id, fromJar: raw['jar'] == true, at: when);
  }
}
