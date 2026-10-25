import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Выход с экрана, который сперва сохраняет себя (TOG-33).
///
/// Холст на выходе снимает свою картинку, это доли секунды. Стрелка и
/// системное «назад», нажатые подряд, запускали выход дважды, и второй `pop`
/// закрывал экран под холстом, а когда закрывать было нечего, приложение
/// падало «Bad state: No element» (Bugsink 20.10 и 23.10.2026). Здесь выход
/// идёт один раз и закрывает только свой экран, пока тот сверху. Если поверх
/// за это время что-то открыли, выход ничего не закрывает и не запирается:
/// следующее «назад» сработает как обычно.
class SingleExit {
  bool _running = false;

  /// Выход уже идёт.
  bool get running => _running;

  Future<void> run(BuildContext context, Future<void> Function() save) async {
    if (_running) return;
    _running = true;
    try {
      await save();
    } catch (error) {
      // не сохранилось — выйти всё равно нужно, человек нажал «назад»
      debugPrint('SingleExit: сохранение перед выходом не удалось: $error');
    }
    if (!context.mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _running = false;
      return;
    }
    Navigator.of(context).pop();
  }
}
