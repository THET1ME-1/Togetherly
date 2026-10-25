/// Стопка контроллеров над Flutter на iPhone, пока идёт реклама (TOG-37).
///
/// Плагин Яндекса показывает ролик своим прозрачным контроллером в стиле
/// `.overCurrentContext`, а уже поверх него SDK кладёт сам ролик. Экран Flutter
/// при этом не исчезает, и приложение не узнаёт, что его накрыли: жизненный
/// цикл стоит на `resumed`, в отчётах Bugsink у всех айфонов `away_s: 0`.
/// Конец ролика остаётся видеть только по событию «закрыто», а оно теряется:
/// за трое суток (22–25.10.2026) на iPhone 592 ролика из 3230 засчитаны, а
/// сундук после них так и не открылся, на Android таких 1,1%.
///
/// Натив описывает стопку тремя признаками, правило — здесь, под тестами.
class AdCoverSnapshot {
  const AdCoverSnapshot({required this.depth, required this.pluginTop, required this.topEmpty});

  /// Сколько контроллеров показано поверх Flutter, один над другим.
  final int depth;

  /// Верхний из них — прозрачный контроллер плагина рекламы.
  final bool pluginTop;

  /// Верхний контроллер пуст: ни своего показанного, ни дочерних
  /// контроллеров, ни видов внутри.
  final bool topEmpty;

  /// Кривой ответ натива читается пустой стопкой: от него не ждут ни показа,
  /// ни закрытия.
  factory AdCoverSnapshot.fromMap(Object? raw) {
    if (raw is! Map) return const AdCoverSnapshot(depth: 0, pluginTop: false, topEmpty: true);
    final depth = raw['depth'];
    return AdCoverSnapshot(
      depth: depth is int && depth > 0 ? depth : 0,
      pluginTop: raw['pluginTop'] == true,
      topEmpty: raw['topEmpty'] != false,
    );
  }

  /// Ролик на экране: SDK положил свой контроллер поверх контроллера плагина,
  /// или нарисовал ролик прямо внутри него.
  bool get adOnScreen => depth >= 2 || (pluginTop && !topEmpty);
}

/// Следит за стопкой во время показа: был ли ролик и ушёл ли он.
///
/// Пустой контроллер плагина в начале показа ещё не реклама: SDK кладёт
/// ролик поверх него мгновением позже. Закрытием считается только уход
/// ролика, который был виден.
class AdCoverTracker {
  bool _sawAd = false;
  bool _closed = false;
  bool _leftover = false;

  /// Ролик был на экране — доказательство показа, даже без событий SDK.
  bool get sawAd => _sawAd;

  /// Ролик, который был виден, ушёл.
  bool get closed => _closed;

  /// Ролик ушёл, а прозрачный контроллер плагина остался: он держит касания,
  /// и приложение выглядит зависшим. Убрать его должен был сам плагин по
  /// событию SDK, которое не пришло.
  bool get leftover => _leftover;

  void onSnapshot(AdCoverSnapshot s) {
    if (s.adOnScreen) {
      _sawAd = true;
      _closed = false;
      _leftover = false;
      return;
    }
    if (!_sawAd) return;
    _closed = true;
    _leftover = s.depth == 1 && s.pluginTop && s.topEmpty;
  }
}
