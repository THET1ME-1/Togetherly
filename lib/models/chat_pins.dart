import 'chat_msg.dart';

/// Закреплённые сообщения чата пары (06.11.2026, как в Telegram): полоска
/// над лентой, строка «Вы закрепили…» в самой ленте и экран со всеми.
///
/// Закреплённое бывает давним, вне загруженной ленты, поэтому список
/// собирается из двух мест: с сервера (`PbDataService.pinnedChat`) и из ленты,
/// куда правки партнёра приходят живыми. По одному id лента свежее.
List<ChatMsg> pinnedMessages(Iterable<ChatMsg> server, Iterable<ChatMsg> loaded) {
  final byId = <String, ChatMsg>{for (final m in server) m.id: m};
  for (final m in loaded) {
    byId[m.id] = m;
  }
  return [
    for (final m in byId.values)
      if (m.isPinned && !m.deleted) m,
  ]..sort((a, b) => a.ts.compareTo(b.ts));
}

/// Какое закреплённое показывает полоска: прежнее, если оно ещё есть, иначе
/// самое новое. -1 — закреплённых нет.
int pinBarIndex(int? current, int count) {
  if (count == 0) return -1;
  if (current == null || current < 0 || current >= count) return count - 1;
  return current;
}

/// После перехода к закреплённому полоска показывает предыдущее, а с самого
/// старого возвращается к новому — так нажатиями обходятся все.
int pinBarNext(int index, int count) => index > 0 ? index - 1 : count - 1;

/// Ключ строк «закрепили», которые встают после последнего сообщения ленты.
const String kPinNotesTail = '';

/// Где в ленте [feed] (по возрастанию `ts`) встают строки «закрепили»: id
/// сообщения → закреплённые, чья строка стоит прямо перед ним, по времени
/// закрепления. Строка встаёт перед первым сообщением позже закрепления, и
/// перед разделителем его дня: закрепили вчера вечером — строка во вчерашнем.
Map<String, List<ChatMsg>> pinNotesBefore(List<ChatMsg> feed) {
  final pins = [
    for (final m in feed)
      if (m.isPinned && !m.deleted) m,
  ]..sort((a, b) => a.pinnedAt!.compareTo(b.pinnedAt!));
  final out = <String, List<ChatMsg>>{};
  var i = 0;
  for (final m in feed) {
    while (i < pins.length && pins[i].pinnedAt! <= m.ts) {
      out.putIfAbsent(m.id, () => []).add(pins[i]);
      i++;
    }
  }
  if (i < pins.length) out[kPinNotesTail] = pins.sublist(i);
  return out;
}

/// Поля записи для закрепления и открепления. Открепить — обнулить: колонки
/// не nullable, ноль и пустая строка значат «не закреплено».
Map<String, dynamic> pinFields(bool pinned, String uid, int now) =>
    pinned ? {'pinned_at': now, 'pinned_by': uid} : {'pinned_at': 0, 'pinned_by': ''};
