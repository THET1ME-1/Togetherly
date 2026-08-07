import 'package:flutter/animation.dart';

/// Гасит контроллер анимации и отдаёт null для поля, где он лежал.
///
/// Второй `dispose()` у одного и того же контроллера в отладке ловит assert, а
/// в релизе доходит до `_ticker!` внутри самого Flutter и роняет приложение:
/// «Null check operator used on a null value». Ровно так падала карта пары —
/// «показать обоих» гасило перелёт, ссылка оставалась в поле, и закрытие экрана
/// гасило тот же контроллер второй раз.
///
/// Писать `_ctrl = disposeAnim(_ctrl)` вместо `_ctrl?.dispose()`: поле само
/// становится пустым, и повторный вызов уже никого не трогает.
AnimationController? disposeAnim(AnimationController? controller) {
  controller?.dispose();
  return null;
}
