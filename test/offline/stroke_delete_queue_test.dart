// Отмена штриха доводится до сервера очередью, а не теряется по дороге.
//
// Жалоба пары 14 августа 2026: «в раскрасках с партнёром рисунок может слетать,
// а отменённые штрихи могут восстановиться». Причина была двойная:
// `CanvasRepository.deleteStroke` отдавал `Future<void>` и проглатывал отказ, а
// экран при исключении возвращал штрих на холст. В итоге штрих исчезал с
// экрана, оставался в базе и всплывал при следующей загрузке.
//
// Теперь репозиторий отдаёт результат, а неудачное удаление уходит в очередь —
// она повторяет с паузами и переживает перезапуск приложения.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final draw = File('lib/screens/draw_screen.dart').readAsStringSync();
  final repo = File('lib/services/canvas_repository.dart').readAsStringSync();
  final outbox = File('lib/services/offline/outbox_service.dart').readAsStringSync();

  test('репозиторий отдаёт результат удаления, а не void', () {
    expect(
      repo.contains('Future<bool> deleteStroke(String strokeId)'),
      isTrue,
      reason: 'отмена обязана знать, дошло ли удаление до сервера',
    );
  });

  test('очередь знает операцию strokeDelete', () {
    expect(outbox.contains("case 'strokeDelete':"), isTrue);
    expect(outbox.contains("k('canvas_strokes', p['id'])"), isTrue,
        reason: 'у операции должен быть ключ записи, иначе порядок разъедется');
    expect(outbox.contains("data.deleteStroke(p['id'] as String? ?? '')"), isTrue,
        reason: 'операция должна что-то делать при исполнении');
  });

  test('каждое удаление штриха на экране подстраховано очередью', () {
    final calls = 'deleteStroke('.allMatches(draw).length;
    final rescues = "enqueue('strokeDelete'".allMatches(draw).length;
    expect(calls, greaterThan(0), reason: 'вызовы удаления пропали — проверьте экран');
    expect(
      rescues,
      greaterThanOrEqualTo(calls),
      reason: 'на каждый вызов удаления нужен запасной путь через очередь: '
          'без него отказ теряется молча и штрих возвращается',
    );
  });

  test('отмена не возвращает штрих на холст при отказе', () {
    // Прежний откат опознавался по возврату записи в _remoteStrokes прямо в
    // обработчике ошибки удаления.
    expect(
      draw.contains('_remoteStrokes = [..._remoteStrokes, removed!]'),
      isFalse,
      reason: 'отменённый штрих не должен всплывать обратно: человек его убрал',
    );
  });
}
