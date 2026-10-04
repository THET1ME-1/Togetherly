import 'dart:async';

import 'package:flutter/gestures.dart';

/// Досылает отмену касанию, у которого так и не пришёл конец.
///
/// Системные жесты некоторых оболочек Android (скриншот тремя пальцами, боковая
/// панель и жесты по краю у Realme и ColorOS) забирают касание себе, и Flutter
/// не получает ни «отпустили», ни «отменили». Список, по которому шло
/// касание, остаётся в режиме перетаскивания и через `IgnorePointer` не пускает
/// нажатия ни к одной кнопке до перезапуска. «Назад» при этом работает,
/// анимации идут (flutter#193549). Так выглядело обращение 231 (Realme 10 Pro,
/// 04.10.2026): после любого действия приложение не нажимается.
///
/// Правило: начинается новое касание, а прежнее молчит дольше [stale], значит,
/// прежнее потеряно, и мы заканчиваем его отменой. По таймеру не отменяем:
/// палец, неподвижно держащий кнопку записи голосового, тоже молчит.
class StalePointerSweeper {
  StalePointerSweeper._();

  static const Duration stale = Duration(seconds: 4);

  static final Map<int, _Pointer> _down = {};
  static bool _installed = false;

  /// Сколько потерянных касаний уже закончено — для теста и журнала.
  static int swept = 0;

  static void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onEvent);
  }

  static void _onEvent(PointerEvent e) {
    if (e is PointerDownEvent) {
      final lost = [
        for (final p in _down.entries)
          if (p.key != e.pointer && e.timeStamp - p.value.at > stale) p,
      ];
      for (final p in lost) {
        _down.remove(p.key);
        swept++;
        // Отмена — отдельным событием после текущего: посреди разбора чужого
        // касания маршрутизатор лучше не трогать.
        scheduleMicrotask(() => GestureBinding.instance.handlePointerEvent(
              PointerCancelEvent(
                pointer: p.key,
                position: p.value.position,
                kind: p.value.kind,
                device: p.value.device,
                timeStamp: e.timeStamp,
              ),
            ));
      }
      _down[e.pointer] = _Pointer(e.timeStamp, e.position, e.kind, e.device);
    } else if (e is PointerMoveEvent) {
      final p = _down[e.pointer];
      if (p != null) _down[e.pointer] = _Pointer(e.timeStamp, e.position, p.kind, p.device);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _down.remove(e.pointer);
    }
  }
}

class _Pointer {
  const _Pointer(this.at, this.position, this.kind, this.device);
  final Duration at;
  final Offset position;
  final PointerDeviceKind kind;
  final int device;
}
