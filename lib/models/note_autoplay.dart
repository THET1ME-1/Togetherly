import 'chat_msg.dart';

/// Какой кружок (или голосовое) включить, когда досмотрели [finishedId].
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
}) =>
    _nextAfter(messages, finishedId, myUid,
        (m) => m.isNote && !m.noteSeen && !seenLocally.contains(m.id));

/// То же для голосовых: следующее непрослушанное голосовое партнёра.
ChatMsg? nextUnheardVoice(
  List<ChatMsg> messages, {
  required String finishedId,
  required String myUid,
  Set<String> heardLocally = const {},
}) =>
    _nextAfter(messages, finishedId, myUid,
        (m) => m.isVoice && !m.voiceHeard && !heardLocally.contains(m.id));

ChatMsg? _nextAfter(
  List<ChatMsg> messages,
  String finishedId,
  String myUid,
  bool Function(ChatMsg) wanted,
) {
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
    if (m.deleted || m.uid == myUid || m.id == finishedId) continue;
    if (!wanted(m)) continue;
    if (m.ts <= done.ts) continue;
    if (next == null || m.ts < next.ts) next = m;
  }
  return next;
}
