/// Очередь роликов ленты: номера, которые скрытая страница платформы уже
/// принесла, а комната ещё не показала.
///
/// Лента приходит кусками и с повторами: каждый ответ `reel_watch_sequence`
/// несёт и текущий ролик, и соседние, а после перехода к следующему часть
/// номеров приезжает снова. Показанный ролик второй раз в очередь не встаёт.
class ReelQueue {
  ReelQueue({this.limit = 60});

  /// Сколько держим в запасе. Лента бесконечная, а комнате хватает десятка.
  final int limit;

  final List<String> _queue = [];
  final Set<String> _known = {};

  /// Номер ролика YouTube: ровно 11 знаков из латиницы, цифр, `-` и `_`.
  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isId(String s) => _id.hasMatch(s);

  /// Номера роликов из ответа платформы, по порядку и без повторов.
  static List<String> idsIn(String text) {
    final out = <String>[];
    final seen = <String>{};
    for (final m in RegExp(r'"videoId":"([A-Za-z0-9_-]{11})"').allMatches(text)) {
      final id = m.group(1)!;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  int get length => _queue.length;

  /// Добавить пришедшее. Возвращает, сколько встало нового.
  int add(Iterable<Object?> ids) {
    var added = 0;
    for (final raw in ids) {
      if (raw is! String || !isId(raw)) continue;
      if (!_known.add(raw)) continue;
      if (_queue.length >= limit) continue;
      _queue.add(raw);
      added++;
    }
    return added;
  }

  /// Забрать до [n] номеров для показа.
  List<String> take(int n) {
    final count = n.clamp(0, _queue.length);
    final out = _queue.sublist(0, count);
    _queue.removeRange(0, count);
    return out;
  }

  /// Ролик уже показан (например, пришёл из ленты партнёра): из очереди вон
  /// и больше не принимать.
  void markShown(String id) {
    _known.add(id);
    _queue.remove(id);
  }

  /// «Обновить рекомендации»: запас выбрасываем, чтобы пошли свежие. Невиденные
  /// номера забываем — платформа вправе прислать их снова, а показанные
  /// остаются в памяти и второй раз не встанут.
  void dropPending() {
    _known.removeAll(_queue);
    _queue.clear();
  }

  /// Последний номер в очереди — от него скрытая страница листает дальше.
  String? get last => _queue.isEmpty ? null : _queue.last;
}
