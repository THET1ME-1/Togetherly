import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Обращение 403 (1.38.0, общая раскраска): «Отменить» горела, а нажатие не
/// делало ничего. Свой штрих на общем холсте после записи на сервере меняет
/// временный id на серверный, а номер действия оставался под старым: отмена
/// не находила его и молча выходила. Правило живёт в `canvas_undo.dart`, здесь
/// — что экран холста им пользуется.
void main() {
  final src = File('lib/screens/draw_screen.dart').readAsStringSync();

  test('при смене id своего штриха номер действия переезжает следом', () {
    // Переименования отдаёт книга общего холста (`SharedStrokes`): у штрихов
    // старого вида id записи узнаётся только из снимка сервера.
    final swap = src.indexOf('updatedMyIds[i] = to');
    expect(swap, greaterThan(0));
    final after = src.substring(swap, swap + 600);
    expect(after, contains('adoptStrokeId(_strokeSeq, _mirrorGroupOf'),
        reason: 'без переезда отмена теряет штрих после ответа сервера');
  });

  test('общий холст поднимает свои прошлые линии в историю отмены', () {
    final remote = src.indexOf('void _onRemoteStrokes(');
    expect(remote, greaterThan(0));
    final body = src.substring(remote, remote + 4000);
    // Список книги, а не сырой снимок: в нём одна линия на все копии мазка,
    // и отмена снимает их разом (TOG-12).
    expect(body, contains('ownStrokeHistory(shown, _myUid)'),
        reason: 'без этого линию прошлого захода в общем холсте не отменить');
  });

  test('отмена берёт номер своего штриха через ownStrokeSeq', () {
    final undo = src.indexOf('Future<void> _undo()');
    expect(undo, greaterThan(0));
    final body = src.substring(undo, undo + 400);
    expect(body, contains('ownStrokeSeq(_strokeSeq, _myStrokeIds.last)'),
        reason: 'штрих без номера (поднятый с диска) тоже обязан отменяться');
  });
}
