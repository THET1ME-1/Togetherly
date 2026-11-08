import 'dart:async';

import 'package:flutter/widgets.dart';

/// Сколько ждём, что клавиатура вернёт отправленный текст.
const Duration kSentTextEcho = Duration(milliseconds: 800);

/// Очищает поле после отправки и не даёт клавиатуре вернуть текст обратно.
///
/// Нажали «отправить», пока клавиатура держит слово недописанным (composing),
/// и она следом присылает своё прежнее состояние: сообщение ушло, а текст снова
/// в поле (отзыв в Google Play на 1.41.0, realme C30). Поэтому [kSentTextEcho]
/// после очистки ровно отправленный текст стираем ещё раз. Набранное заново
/// не трогаем: за доли секунды то же сообщение не перепечатать.
///
/// [alive] — жив ли ещё экран: закрытый экран уже выбросил контроллер.
void clearSentText(TextEditingController controller, String sent, bool Function() alive) {
  controller.clear();
  final text = sent.trim();
  if (text.isEmpty) return;

  void echo() {
    if (controller.text.trim() != text) return;
    // Не внутри рассылки самого контроллера: поле сначала примет значение
    // клавиатуры, потом мы его сотрём.
    scheduleMicrotask(() {
      if (alive() && controller.text.trim() == text) controller.clear();
    });
  }

  controller.addListener(echo);
  Future<void>.delayed(kSentTextEcho, () {
    if (alive()) controller.removeListener(echo);
  });
}
