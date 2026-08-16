// Нарисованное не стирается, когда запрос до сервера не дошёл.
//
// Жалоба с 1.28.0 (16 августа 2026): «лагает очень приложение, когда рисуешь по
// клеточкам, всё стирает, холст дрожит». В пиксельном режиме штрих — это одна
// клетка, и закрашивая фон человек шлёт их десятками в секунду. Часть запросов
// не проходит (сеть, лимит сервера), а экран на отказ просто убирал штрих:
//
//     .catchError((e) {
//       _pendingLocalStrokes.remove(stroke.id);   // клетка исчезает с холста
//
// Теперь отказ уходит в очередь: она повторяет с паузами и переживает
// перезапуск приложения, а клетка остаётся там, где её нарисовали.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final draw = File('lib/screens/draw_screen.dart').readAsStringSync();
  final outbox =
      File('lib/services/offline/outbox_service.dart').readAsStringSync();

  test('очередь знает операцию strokeAdd', () {
    expect(outbox.contains("case 'strokeAdd':"), isTrue,
        reason: 'без своей ветки очередь операцию не исполнит');
    expect(outbox.contains("k('canvas_strokes', p['id'])"), isTrue,
        reason: 'ключ записи держит порядок правок одного штриха');
    expect(outbox.contains('createStroke('), isTrue,
        reason: 'исполнение должно и правда создавать штрих');
  });

  test('отказ отправки не убирает штрих с холста', () {
    expect(
      draw.contains('_pendingLocalStrokes.remove(stroke.id)'),
      isFalse,
      reason: 'нарисованную клетку нельзя стирать из-за сбоя сети: '
          'её ставят в очередь и повторяют',
    );
  });

  test('каждый коммит штриха подстрахован очередью', () {
    expect(draw.contains("enqueue('strokeAdd'"), isTrue,
        reason: 'запасной путь для добавления штриха');
  });

  test('отменённый штрих снимается с очереди, а не воскресает', () {
    expect(draw.contains("enqueue('strokeCancel'"), isTrue,
        reason: 'отмена ещё не улетевшего штриха обязана гасить задачу: '
            'иначе очередь пришлёт его позже и он вернётся на холст');
    expect(outbox.contains("case 'strokeCancel':"), isTrue);
    expect(outbox.contains('_dropQueued('), isTrue,
        reason: 'гашение удаляет задачу из очереди, а не добавляет новую');
  });
}
