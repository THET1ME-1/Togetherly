import 'dart:async';

import 'package:flutter/widgets.dart';

/// Выход с экрана, который на прощание сохраняет себя.
///
/// Экран закрывается сразу, а сохранение доделывается после (TOG-39): холст
/// ждал, пока снимется картинка и перепишется список всех холстов, и
/// «назад» на iPhone SE выглядело нерабочим (обращение 471). Сохранение
/// начинается до ухода, пока экран на месте: снимок берёт кадр с него.
///
/// Выход идёт один раз (TOG-33): стрелка и системное «назад» подряд
/// закрывали ещё и экран под холстом, а когда закрывать было нечего,
/// приложение падало «Bad state: No element». Если экран уже не сверху,
/// выход ничего не трогает и не запирается.
class SingleExit {
  bool _running = false;

  /// Выход уже идёт.
  bool get running => _running;

  void run(BuildContext context, Future<void> Function() save) {
    if (_running) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _running = true;
    unawaited(_finish(save));
    Navigator.of(context).pop();
  }

  Future<void> _finish(Future<void> Function() save) async {
    try {
      await save();
    } catch (error) {
      // не сохранилось — человек уже ушёл, ронять тут нечего
      debugPrint('SingleExit: сохранение после выхода не удалось: $error');
    }
  }
}
