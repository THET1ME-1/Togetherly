import 'dart:async';

import 'package:flutter/widgets.dart';

/// Подсказки показываются, только когда на главной спокойно.
///
/// Очередь подсказок стартует с главной сразу, а лист покупки Плюса и другие
/// окна выезжают через пару секунд после входа — и подсказка садилась прямо
/// на лист. Теперь она ждёт: окон поверх нет, на главной человек уже какое-то
/// время, и после последней смены экрана прошло несколько спокойных секунд.

/// Сколько тишины нужно после последнего открытия или закрытия окна.
const Duration hintQuiet = Duration(seconds: 5);

/// Сколько человек должен пробыть на главной: окна при входе выезжают не
/// сразу, а с задержкой на сеть.
const Duration hintSettle = Duration(seconds: 15);

bool hintMayShow({
  required int openPopups,
  required Duration sinceLastChange,
  required Duration sinceHomeShown,
}) =>
    openPopups == 0 && sinceLastChange >= hintQuiet && sinceHomeShown >= hintSettle;

class HintCalm {
  HintCalm._();

  static final HintCalm instance = HintCalm._();

  @visibleForTesting
  factory HintCalm.forTest() => HintCalm._();

  /// Наблюдатель для `MaterialApp.navigatorObservers`.
  late final NavigatorObserver observer = _PopupObserver(this);

  /// Сколько окон (листов, диалогов) открыто прямо сейчас.
  int openPopups = 0;

  DateTime _lastChange = DateTime.now();
  DateTime? _homeShownAt;

  void _changed() => _lastChange = DateTime.now();

  /// Главная показана: с этого момента отсчитывается [hintSettle].
  void homeShown() => _homeShownAt ??= DateTime.now();

  /// Ждёт спокойного момента. [ready] спрашивается на каждом шаге: человек мог
  /// уйти с главной. Возвращает false, если спокойного момента не дождались.
  Future<bool> waitCalm(bool Function() ready, {Duration timeout = const Duration(minutes: 3)}) async {
    final until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      final now = DateTime.now();
      final home = _homeShownAt;
      if (home != null &&
          ready() &&
          hintMayShow(
            openPopups: openPopups,
            sinceLastChange: now.difference(_lastChange),
            sinceHomeShown: now.difference(home),
          )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }
}

class _PopupObserver extends NavigatorObserver {
  _PopupObserver(this.calm);

  final HintCalm calm;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) calm.openPopups++;
    calm._changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _gone(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _gone(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _gone(oldRoute);
    if (newRoute is PopupRoute) calm.openPopups++;
    calm._changed();
  }

  void _gone(Route<dynamic> route) {
    if (route is PopupRoute && calm.openPopups > 0) calm.openPopups--;
    calm._changed();
  }
}
