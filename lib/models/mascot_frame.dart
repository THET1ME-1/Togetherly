/// Счёт кадров пиксельного маскота.
///
/// Вынесено из виджета, когда анимация переехала с `Timer.periodic` на
/// `Ticker`: таймер живёт по своим часам и тикает даже под чужим экраном, а
/// тикер будит виджет там, где рисуется кадр, и замирает вместе с экраном.
/// Сама анимация от этого не меняется — те же кадры, та же скорость.
class MascotFrameStep {
  const MascotFrameStep({
    required this.frame,
    required this.looped,
    required this.finished,
  });

  /// Кадр, который показываем дальше.
  final int frame;

  /// Круг закончился — повод разыграть свою сцену.
  final bool looped;

  /// Разовое состояние доиграно, персонаж возвращается к обычной жизни.
  final bool finished;

  @override
  bool operator ==(Object other) =>
      other is MascotFrameStep &&
      other.frame == frame &&
      other.looped == looped &&
      other.finished == finished;

  @override
  int get hashCode => Object.hash(frame, looped, finished);

  @override
  String toString() =>
      'MascotFrameStep(frame: $frame, looped: $looped, finished: $finished)';
}

/// Следующий кадр петли.
MascotFrameStep nextMascotFrame({
  required int frame,
  required int cols,
  required bool oneShot,
}) {
  if (cols <= 0) {
    return const MascotFrameStep(frame: 0, looped: false, finished: false);
  }
  final next = frame + 1;
  if (next < cols) {
    return MascotFrameStep(frame: next, looped: false, finished: false);
  }
  if (oneShot) {
    return MascotFrameStep(frame: frame, looped: true, finished: true);
  }
  return const MascotFrameStep(frame: 0, looped: true, finished: false);
}

/// Сколько держится один кадр. Ноль и мусор дают прежнее умолчание в десять
/// кадров в секунду.
Duration mascotFrameStep(int fps) {
  final rate = fps <= 0 ? 10 : fps;
  return Duration(milliseconds: (1000 / rate).round());
}

/// Виден ли персонаж на экране (с запасом в пол-экрана сверху и снизу).
///
/// Галерея строит всех разом — `GridView` с `shrinkWrap` не ленивый, — и без
/// этой проверки тикали бы все тридцать персонажей сразу. Анимация от этого не
/// исчезает: за краем экрана она замирает, у края снова идёт.
bool mascotOnScreen({
  required double top,
  required double bottom,
  required double screenHeight,
}) {
  if (screenHeight <= 0) return true;
  final margin = screenHeight / 2;
  return bottom > -margin && top < screenHeight + margin;
}
