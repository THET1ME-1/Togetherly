import 'chat_msg.dart';

/// Какой кружок включить, когда досмотрели [finishedId].
///
/// Партнёр обычно шлёт несколько кружков подряд, и включать каждый руками
/// утомительно — как в Telegram, непросмотренные играют один за другим.
/// Берём только кружки партнёра, которые ещё не смотрели, и только новее
/// досмотренного: пересматривая старое, человек не должен улетать по ленте.
/// [seenLocally] — отмеченные в этом заходе, пока отметка не доехала.
ChatMsg? nextUnseenNote(
  List<ChatMsg> messages, {
  required String finishedId,
  required String myUid,
  Set<String> seenLocally = const {},
}) {
  ChatMsg? done;
  for (final m in messages) {
    if (m.id == finishedId) {
      done = m;
      break;
    }
  }
  if (done == null) return null;
  ChatMsg? next;
  for (final m in messages) {
    if (!m.isNote || m.deleted || m.uid == myUid) continue;
    if (m.noteSeen || seenLocally.contains(m.id) || m.id == finishedId) continue;
    if (m.ts <= done.ts) continue;
    if (next == null || m.ts < next.ts) next = m;
  }
  return next;
}
