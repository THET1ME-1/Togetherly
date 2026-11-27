import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

/// Чем кончилась просьба поставить виджет на рабочий стол.
enum WidgetPinOutcome {
  /// Виджет на столе.
  placed,

  /// Система спросила, человек передумал.
  cancelled,

  /// Ни окна системы, ни виджета: лончер молча отказал.
  silent,
}

/// Ждёт итог просьбы поставить виджет, глядя на сам рабочий стол.
///
/// Ответ `requestPinAppWidget` ничего не значит: лончер Xiaomi отвечает
/// «принято», а без разрешения «Ярлыки на рабочем столе» не ставит ничего, и
/// приложение показывало зелёное «Виджет добавлен» (обращения 25.11.2026).
/// Поэтому [count] — сколько таких виджетов на столе сейчас, [before] — сколько
/// было до просьбы.
///
/// Окно системы уводит приложение с переднего плана: пока оно открыто, человек
/// решает сколько угодно. Не ушло за [quiet] и виджета нет — лончер промолчал.
/// Вернулось без виджета и за [afterReturn] он не появился — человек отказался.
Future<WidgetPinOutcome> watchWidgetPin({
  required Future<int> Function() count,
  required int before,
  Duration quiet = const Duration(seconds: 4),
  Duration afterReturn = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 400),
  Duration patience = const Duration(minutes: 2),
}) async {
  // Окно системы могло открыться раньше, чем мы начали слушать: слушатель
  // прошлых смен не повторяет, поэтому нынешнее состояние берём сразу.
  final state = WidgetsBinding.instance.lifecycleState;
  var lostFocus = state != null && state != AppLifecycleState.resumed;
  Duration? returnedAt;
  // Время считается шагами ожидания, а не часами: так его видят и тесты, и
  // запрос числа виджетов (миллисекунды) в счёт не идёт.
  var now = Duration.zero;
  final listener = AppLifecycleListener(onStateChange: (state) {
    if (state == AppLifecycleState.resumed) {
      if (lostFocus) returnedAt = now;
    } else {
      lostFocus = true;
      returnedAt = null;
    }
  });
  try {
    while (true) {
      await Future<void>.delayed(step);
      now += step;
      if (await count() > before) return WidgetPinOutcome.placed;
      if (!lostFocus && now >= quiet) return WidgetPinOutcome.silent;
      final back = returnedAt;
      if (back != null && now - back >= afterReturn) return WidgetPinOutcome.cancelled;
      if (now >= patience) {
        return lostFocus ? WidgetPinOutcome.cancelled : WidgetPinOutcome.silent;
      }
    }
  } finally {
    listener.dispose();
  }
}

/// Сколько виджетов класса [className] сейчас на рабочем столе.
Future<int> installedWidgetCount(String className) async {
  try {
    final installed = await HomeWidget.getInstalledWidgets();
    return installed
        .where((w) => (w.androidClassName ?? '').split('.').last == className)
        .length;
  } catch (_) {
    return 0;
  }
}
