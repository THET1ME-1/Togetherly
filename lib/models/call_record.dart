/// История звонков в комнате и лентах: каждый состоявшийся разговор ложится
/// в чат пары записью «Звонок · 4:12» (поле `chat_messages.call_ms`).
///
/// Разговор видят оба телефона, а запись нужна одна. Пишет тот, чей uid
/// меньше: оба приходят к одному ответу без переговоров, как при выборе
/// ведущего в комнате. Собеседник неизвестен — пишем сами: второй записи
/// тогда тоже некому сделать.
bool writesCallRecord({required String me, required String peer}) =>
    peer.isEmpty || me.compareTo(peer) < 0;

/// Короче этого разговор не записываем: это сорвавшийся звонок, а не беседа.
const Duration kMinCallRecord = Duration(seconds: 2);

/// «4:12», а с часа — «1:02:03».
String callDuration(int ms) {
  final total = (ms / 1000).round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}

/// Текст записи — его увидят и сборки, которые карточку звонка не знают.
String callRecordText(String title, int ms) => '$title · ${callDuration(ms)}';
