/// Одно нажатие на виджет — одно действие.
///
/// Нажатие доходит до главной разными путями: стартовая ссылка home_widget,
/// его поток, поток DeepLinkService (туда пишут системный канал маршрутов,
/// стартовая ссылка app_links и его поток) и буфер холодного старта. Без
/// фильтра лист заметки открывался столько раз, сколько путей сработало, и
/// «назад» приходилось жать несколько раз (TOG-13). Та же ссылка в пределах
/// [window] считается повтором.
class WidgetTapDedup {
  WidgetTapDedup({this.window = const Duration(seconds: 3)});

  final Duration window;
  final Map<String, DateTime> _last = {};

  bool admit(Uri uri, DateTime now) {
    final key = uri.toString();
    final last = _last[key];
    if (last != null && now.difference(last) < window) return false;
    _last[key] = now;
    return true;
  }
}
