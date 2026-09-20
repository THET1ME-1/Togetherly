import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Открытый пин обязан жить свежей записью, а не снимком из конструктора.
///
/// Закладка, закрепление и реакции правят локальный кэш, а экран об этом
/// узнавал только при следующем открытии: кнопки стояли нетронутыми, и
/// человек выходил и заходил снова, чтобы увидеть своё же нажатие.
void main() {
  final src = File('lib/screens/memory_lane/detail.dart').readAsStringSync();

  test('экран подписан на поток записи и отписывается', () {
    expect(src.contains('MemoryRepository().watch(widget.groupId).listen'),
        isTrue,
        reason: 'без подписки кнопки не обновятся до перезахода');
    expect(src.contains('_watch?.cancel()'), isTrue,
        reason: 'подписка обязана сниматься в dispose');
  });

  test('тулбар читает живую запись, а не widget.memory', () {
    final from = src.indexOf('Widget _momentDock(');
    expect(from, greaterThan(0));
    final dock = src.substring(from, src.indexOf('\n  /// Открыть кадр', from));
    expect(dock.contains('widget.memory'), isFalse,
        reason: 'снимок не меняется после нажатия');
  });

  test('закрепление считается от живой записи', () {
    expect(src.contains('isPinned: !_memory.isPinned'), isTrue,
        reason: 'от снимка второе нажатие повторяло первое');
    expect(src.contains('widget.onTogglePin'), isFalse,
        reason: 'колбэк родителя нёс устаревшее значение');
  });
}
