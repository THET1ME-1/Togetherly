// Карточка «Цикл» не отправляет на витрину того, кто уже заплатил.
//
// Флаг `users.plus` читается с сервера, и до первого ответа он равен false —
// то есть гейт какое-то время говорит «не куплено» о купившем. Правило проекта
// с 19 августа 2026: всё, что предлагает покупку, обязано дождаться ответа.
// Главный экран его соблюдает, а карточка цикла спрашивала гейт сразу и уводила
// на экран Togetherly+, где человеку сообщали «Плюс ваш, всё открыто» — цикла
// он так и не видел. Жалобы 01.09.2026: «мы нажали и нету такого, даже если
// есть подписка, нету цикла», «приобрели подписку +, но не могу найти календарь
// цикла».
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/cycle_gate.dart';
import 'package:love_app/services/plus_access.dart';

void main() {
  test('куплено — открываем отметки', () {
    expect(cycleTapAction(gate: PlusGate.open, known: true), CycleTap.open);
    // Даже если ответ ещё не прочитан: открытый гейт сам по себе значит покупку.
    expect(cycleTapAction(gate: PlusGate.open, known: false), CycleTap.open);
  });

  test('не куплено и это точно известно — предлагаем покупку', () {
    expect(cycleTapAction(gate: PlusGate.locked, known: true), CycleTap.offer);
  });

  test('ответ ещё не пришёл — ждём, а не гоним на витрину', () {
    expect(cycleTapAction(gate: PlusGate.locked, known: false), CycleTap.wait);
  });

  test('на платформе без Togetherly+ вести некуда', () {
    expect(cycleTapAction(gate: PlusGate.hidden, known: true), CycleTap.nothing);
    expect(cycleTapAction(gate: PlusGate.hidden, known: false), CycleTap.nothing);
  });
}
