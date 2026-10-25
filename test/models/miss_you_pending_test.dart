import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/miss_you_pending.dart';
import 'package:love_app/models/miss_you_state.dart';

/// TOG-40, обращение 377 (iPhone, 25.10.2026): «Думаю о тебе» и «Хочу обнять»
/// уходили, но число на плитке стояло, пока не выйдешь с экрана. Своё нажатие
/// обязано отозваться сразу: и общим счётом, и счётом своего импульса.
void main() {
  final t0 = DateTime(2026, 10, 25, 12);

  MissYouEntry entry(int count, Map<String, int> byVibe) =>
      MissYouEntry(uid: 'me', count: count, lastVibe: '', lastVibeText: '', byVibe: byVibe);

  test('импульс сразу прибавляет и к общему счёту, и к своему виду', () {
    final p = const MissYouPending()
        .confirm(entry(10, {'thinking_of_you': 3}), now: t0)
        .tap('thinking_of_you', t0);
    expect(p.total, 11, reason: 'сервер считает любой импульс в общий счёт');
    expect(p.vibe('thinking_of_you'), 4);
    expect(p.vibe('want_hug'), 0);
  });

  test('сорвалась отправка — надбавка снимается', () {
    final p = const MissYouPending()
        .confirm(entry(10, {'want_hug': 2}), now: t0)
        .tap('want_hug', t0)
        .failed('want_hug');
    expect(p.total, 10);
    expect(p.vibe('want_hug'), 2);
  });

  test('сервер подтвердил — надбавка становится его числом, а не удваивается', () {
    final p = const MissYouPending()
        .confirm(entry(10, {'want_hug': 2}), now: t0)
        .tap('want_hug', t0)
        .confirm(entry(11, {'want_hug': 3}), now: t0.add(const Duration(seconds: 1)));
    expect(p.total, 11);
    expect(p.vibe('want_hug'), 3);
    expect(p.waiting, isFalse);
  });

  test('старый снимок числа назад не двигает', () {
    final p = const MissYouPending()
        .confirm(entry(11, {'want_hug': 3}), now: t0)
        .confirm(entry(10, {'want_hug': 2}), now: t0);
    expect(p.total, 11);
    expect(p.vibe('want_hug'), 3);
  });

  test('«Скучаю» с большой кнопки идёт в общий счёт и в свой вид', () {
    final p = const MissYouPending().confirm(entry(5, const {}), now: t0).tap('miss_you', t0);
    expect(p.total, 6);
    expect(p.vibe('miss_you'), 1);
  });

  test('без подтверждения надбавка живёт свой срок и уходит', () {
    final p = const MissYouPending()
        .confirm(entry(10, {'thinking_of_you': 3}), now: t0)
        .tap('thinking_of_you', t0)
        .expire(t0.add(const Duration(seconds: 11)));
    expect(p.total, 10);
    expect(p.vibe('thinking_of_you'), 3);
    expect(p.waiting, isFalse);
  });
}
