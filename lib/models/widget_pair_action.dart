/// Нажатие на виджет, которому нужна пара, пока пара ещё не загрузилась.
///
/// Виджет нажимают чаще всего на закрытом приложении. Ссылка приходит на
/// главную раньше, чем приезжает пара, и проверка «пара есть» её отбрасывала:
/// человек жал на «Чем заняты» и оказывался на главной, а лист выбора занятия
/// приходилось искать самому (27.11.2026). Так же терялись заметка, холст,
/// «Скучаю» и настроение с виджета; отложенной была только карта.
///
/// Нажатие ждёт пару не дольше [wait]: человек без пары не должен через
/// минуту получить лист, о котором уже забыл.
class WidgetPairAction {
  WidgetPairAction({this.wait = const Duration(seconds: 45)});

  final Duration wait;
  Uri? _uri;
  DateTime? _at;

  /// Отложить нажатие до появления пары. Новое нажатие заменяет прежнее.
  void hold(Uri uri, DateTime now) {
    _uri = uri;
    _at = now;
  }

  /// Забрать отложенное нажатие, если оно ещё не устарело.
  Uri? take(DateTime now) {
    final uri = _uri, at = _at;
    _uri = null;
    _at = null;
    if (uri == null || at == null) return null;
    if (now.difference(at) > wait) return null;
    return uri;
  }
}

/// Ссылки виджетов, которые без пары сделать нечего.
const Set<String> kWidgetHostsNeedingPair = {
  'map',
  'doing',
  'note',
  'draw',
  'miss',
  'mood',
  'memory_lane',
};

bool widgetActionNeedsPair(Uri uri) => kWidgetHostsNeedingPair.contains(uri.host);
