import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/waiting_cancel.dart';

/// «Ждём человека» — вещь для тех, кому есть кого ждать, а не первый экран.
///
/// Экран «позовите свою половинку» показывается один раз, сразу после
/// регистрации, и на нём стояла карточка «пара заранее» — та самая, что
/// открывает лист «Ждём человека». Новичок читает «Завести пару» и решает,
/// что это и есть создание пары: «оно появляется, и они думают, что это
/// создание пары, а не ожидание, путаются» (19.08.2026). Вход остаётся на
/// экране связи, где человек уже понимает, что к чему.
void main() {
  test('на экране новичка нет входа в ожидание', () {
    final source =
        File('lib/screens/invite_partner_screen.dart').readAsStringSync();
    expect(source.contains('WaitingSetupSheet'), isFalse,
        reason: 'Лист ожидания не открывается с первого экрана');
    expect(source.contains('_keepSeatCard('), isFalse,
        reason: 'И карточки-приманки там тоже нет');
  });

  test('вход в ожидание остался на экране связи', () {
    final source =
        File('lib/screens/connect_partner_screen.dart').readAsStringSync();
    expect(source.contains('WaitingSetupSheet.show'), isTrue,
        reason: 'Тем, кому есть кого ждать, путь остаётся');
  });

  group('waitingCancelOutcome', () {
    // «Разорвать ожидание не получается»: человек жмёт «Больше не жду», а
    // сервер отвечает «Место уже занято» — партнёр к тому времени уже вошёл
    // по коду, и режима ожидания на сервере нет. Приложение показывало
    // ошибку, человек жал снова: шесть отказов за секунду в журнале
    // 18.08.2026. Ждать тут больше некого, поэтому такой ответ — успех.
    test('сервер согласился — ожидание снято', () {
      expect(waitingCancelOutcome(ok: true, message: ''),
          WaitingCancelOutcome.cancelled);
    });

    test('место уже занято — значит ждать некого', () {
      expect(waitingCancelOutcome(ok: false, message: 'Место уже занято'),
          WaitingCancelOutcome.alreadyPaired);
    });

    test('пара не найдена — ожидания тоже нет', () {
      expect(waitingCancelOutcome(ok: false, message: 'Пара не найдена'),
          WaitingCancelOutcome.alreadyPaired);
    });

    test('уже отменено — это успех, а не ошибка', () {
      expect(waitingCancelOutcome(ok: false, message: 'already'),
          WaitingCancelOutcome.alreadyPaired);
    });

    test('сеть отвалилась — честная ошибка', () {
      expect(waitingCancelOutcome(ok: false, message: ''),
          WaitingCancelOutcome.failed);
      expect(
          waitingCancelOutcome(ok: false, message: 'Сервер не отвечает'),
          WaitingCancelOutcome.failed);
    });
  });

  test('отмена ожидания слушается правила, а не голого «не вышло»', () {
    final source =
        File('lib/models/connections_manager.dart').readAsStringSync();
    final from = source.indexOf('Future<bool> cancelWaitingPair(');
    expect(from, greaterThan(-1), reason: 'Отмена на месте');
    final body = source.substring(from, from + 1600);
    expect(body.contains('waitingCancelOutcome('), isTrue,
        reason: 'Ответ сервера разбирается правилом');
    expect(body.contains('WaitingCancelOutcome.alreadyPaired'), isTrue,
        reason: 'Занятое место — не ошибка, а снятое ожидание');
    expect(body.contains('clearWaiting()'), isTrue,
        reason: 'Карточка уходит с экрана, а не остаётся висеть');
  });
}
