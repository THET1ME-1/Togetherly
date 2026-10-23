import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/network/staggered_race.dart';

/// Попытка, исход которой решает сам тест.
class _Manual {
  final completer = Completer<String>();
  var started = false;
  var cancelled = false;

  RaceAttempt<String> start() {
    started = true;
    return RaceAttempt(completer.future, () => cancelled = true);
  }
}

void main() {
  const stagger = Duration(milliseconds: 50);

  test('первая ответила до нахлёста — вторая не стартует', () async {
    final first = _Manual();
    final second = _Manual();
    final race = staggeredRace([first.start, second.start], stagger: stagger);
    first.completer.complete('основной');
    final win = await race;
    expect(win.value, 'основной');
    expect(win.index, 0);
    await Future<void>.delayed(stagger * 2);
    expect(second.started, isFalse);
  });

  test('первая молчит — после нахлёста стартует вторая, побеждает, первая прерывается',
      () async {
    final first = _Manual();
    final second = _Manual();
    final race = staggeredRace([first.start, second.start], stagger: stagger);
    await Future<void>.delayed(stagger * 2);
    expect(second.started, isTrue);
    second.completer.complete('запасной');
    final win = await race;
    expect(win.index, 1);
    expect(first.cancelled, isTrue);
  });

  test('первая упала сразу — вторая стартует, не дожидаясь нахлёста', () async {
    final first = _Manual();
    final second = _Manual();
    final race = staggeredRace(
      [first.start, second.start],
      stagger: const Duration(hours: 1),
    );
    first.completer.completeError(StateError('нет пути'));
    await Future<void>.delayed(Duration.zero);
    expect(second.started, isTrue);
    second.completer.complete('запасной');
    expect((await race).index, 1);
  });

  test('запасной упал — основной ждём до конца, как будто гонки нет', () async {
    final first = _Manual();
    final second = _Manual();
    final race = staggeredRace([first.start, second.start], stagger: stagger);
    await Future<void>.delayed(stagger * 2);
    second.completer.completeError(StateError('нет IPv6'));
    await Future<void>.delayed(stagger);
    first.completer.complete('основной, медленно');
    expect((await race).value, 'основной, медленно');
  });

  test('упали все — летит ошибка основного пути, а не запасного', () async {
    final first = _Manual();
    final second = _Manual();
    final race = staggeredRace([first.start, second.start], stagger: stagger);
    first.completer.completeError(StateError('основной'));
    await Future<void>.delayed(Duration.zero);
    second.completer.completeError(StateError('запасной'));
    await expectLater(
      race,
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'основной')),
    );
  });

  test('опоздавший успех проигравшего отдаётся на уборку', () async {
    final first = _Manual();
    final second = _Manual();
    final discarded = <String>[];
    final race = staggeredRace(
      [first.start, second.start],
      stagger: stagger,
      discard: discarded.add,
    );
    await Future<void>.delayed(stagger * 2);
    second.completer.complete('запасной');
    await race;
    first.completer.complete('основной поздно');
    await Future<void>.delayed(Duration.zero);
    expect(discarded, ['основной поздно']);
  });

  test('прерывание до победы отменяет все начатые попытки и роняет гонку', () async {
    final first = _Manual();
    final second = _Manual();
    final abort = Completer<void>();
    final race = staggeredRace(
      [first.start, second.start],
      stagger: stagger,
      abort: abort.future,
    );
    await Future<void>.delayed(stagger * 2);
    abort.complete();
    await expectLater(race, throwsA(anything));
    expect(first.cancelled, isTrue);
    expect(second.cancelled, isTrue);
  });
}
