// Счёт времени на экране для званий (план 2026-11-05-ranks-by-hours, задача 4):
// считается, пока приложение открыто, и не дольше 10 минут после касания —
// забытый открытый телефон не набирает «Легенду».
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/app_time_counter.dart';

void main() {
  final t0 = DateTime(2026, 11, 5, 12);
  DateTime at(int sec) => t0.add(Duration(seconds: sec));

  test('открыто минуту — минута', () {
    final c = AppTimeCounter()..screen(true, at(0));
    c.tick(at(60));
    expect(c.pendingSeconds, 60);
  });

  test('свёрнутое время не считается', () {
    final c = AppTimeCounter()..screen(true, at(0));
    c.screen(false, at(30));
    c.tick(at(600));
    c.screen(true, at(600));
    c.tick(at(630));
    expect(c.pendingSeconds, 60);
  });

  test('без касаний считается не больше 10 минут', () {
    final c = AppTimeCounter()..screen(true, at(0));
    c.tick(at(15 * 60));
    expect(c.pendingSeconds, 10 * 60);
  });

  test('касание после простоя снова включает счёт', () {
    final c = AppTimeCounter()..screen(true, at(0));
    c.tick(at(20 * 60));
    c.touch(at(20 * 60));
    c.tick(at(21 * 60));
    expect(c.pendingSeconds, 11 * 60);
  });

  test('редкие тики не теряют доли секунд', () {
    final c = AppTimeCounter()..screen(true, at(0));
    for (var ms = 700; ms <= 7000; ms += 700) {
      c.tick(t0.add(Duration(milliseconds: ms)));
    }
    expect(c.pendingSeconds, 7);
  });

  test('отправленное вычитается, остаток копится дальше', () {
    final c = AppTimeCounter()..screen(true, at(0));
    c.tick(at(100));
    c.sent(60);
    expect(c.pendingSeconds, 40);
  });

  test('часы телефона назад не дают отрицательного', () {
    final c = AppTimeCounter()..screen(true, at(100));
    c.tick(at(50));
    expect(c.pendingSeconds, 0);
  });
}
