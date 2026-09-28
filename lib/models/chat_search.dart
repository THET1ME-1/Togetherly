/// Поиск по переписке (28.09.2026): вкладки и фильтр для сервера.
///
/// Ищет hotpath: `text ~ 'слово'` там превращается в ILIKE внутри своей пары
/// (`searchable` у `chat_messages`), остальное — обычные условия.
enum ChatSearchKind { all, memories, voice, notes, links }

/// Минимум букв для поиска по тексту: одна буква находит полпереписки.
const int kChatSearchMinChars = 2;

String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

/// Фильтр PocketBase для вкладки [kind] и строки [query]. null — искать
/// нечего (на вкладке «Всё» строка короче минимума).
String? chatSearchFilter({
  required String groupId,
  required ChatSearchKind kind,
  String query = '',
  int? beforeTs,
}) {
  final q = query.trim();
  final parts = <String>["group_id = '${_esc(groupId)}'", 'deleted != true'];
  switch (kind) {
    case ChatSearchKind.all:
      if (q.length < kChatSearchMinChars) return null;
      parts.add("text ~ '${_esc(q)}'");
    case ChatSearchKind.memories:
      parts.add("pin_id != ''");
    case ChatSearchKind.voice:
      parts.add("voice_url != ''");
    case ChatSearchKind.notes:
      parts.add("note_url != ''");
    case ChatSearchKind.links:
      parts.add("text ~ 'http'");
      if (q.length >= kChatSearchMinChars) parts.add("text ~ '${_esc(q)}'");
  }
  if (beforeTs != null) parts.add('ts < $beforeTs');
  return parts.join(' && ');
}

/// Первая ссылка в тексте — для вкладки «Ссылки».
String? firstLink(String text) =>
    RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);

/// Где в тексте совпадение — для подсветки. Без учёта регистра, как сервер.
List<(int, int)> matchRanges(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final t = text.toLowerCase();
  final out = <(int, int)>[];
  var i = t.indexOf(q);
  while (i >= 0) {
    out.add((i, i + q.length));
    i = t.indexOf(q, i + q.length);
  }
  return out;
}
