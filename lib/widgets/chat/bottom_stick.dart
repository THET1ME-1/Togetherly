import 'package:flutter/widgets.dart';

/// Держит ленту чата у низа, пока та меняет высоту без прокрутки.
///
/// Лента не перевёрнута, и её низ — `maxScrollExtent`, который
/// `ListView.builder` до раскладки последних рядов знает только по оценке.
/// Прыжок вниз при открытии попадал в оценку, ряды у низа выходили выше
/// средних (фото, голосовые, длинный текст), догружались картинки, и человек
/// оказывался над новыми сообщениями: «в самом чате я где-то сверху,
/// приходится отматывать вниз» (обращение 256, 15.10.2026).
///
/// Пока [active] стоит, любое изменение размеров ленты довозит её до низа:
/// достроились ряды, догрузилась картинка, открылась клавиатура. Начало
/// прокрутки флаг снимает, конец прокрутки у самого низа ставит обратно.
class BottomStick {
  BottomStick(this.controller);

  final ScrollController controller;

  /// Держать ли низ сейчас. Экран ставит его сам там, где прыгает вниз:
  /// прыжка может и не быть (лента короче экрана), а вырасти она ещё может.
  bool active = false;

  /// Конец прокрутки ближе этого к низу снова держит низ.
  static const double _rearm = 24;

  /// Обернуть ленту: оба слушателя стоят снаружи прокрутки.
  Widget wrap(Widget list) => NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: list,
        ),
      );

  /// Сюда приходят и программные прыжки: `jumpTo` шлёт начало и конец разом,
  /// поэтому после прыжка вниз флаг встаёт сам, а после прыжка к цитате или
  /// найденному сообщению снимается.
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      active = false;
    } else if (n is ScrollEndNotification) {
      active = n.metrics.maxScrollExtent - n.metrics.pixels < _rearm;
    }
    return false;
  }

  /// Уведомление приходит уже после кадра, так что прыгать здесь можно сразу.
  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth != 0 || !active || !controller.hasClients) return false;
    final pos = controller.position;
    if (pos.maxScrollExtent - pos.pixels > 0.5) {
      controller.jumpTo(pos.maxScrollExtent);
    }
    return false;
  }
}
