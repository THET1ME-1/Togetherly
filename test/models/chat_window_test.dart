import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_window.dart';

void main() {
  int ts(int x) => x;
  final all = List<int>.generate(100, (i) => i * 10); // 0, 10 … 990

  test('без нижней границы — новейшие limit', () {
    final w = chatWindow<int>(all, limit: 30, floorTs: null, tsOf: ts);
    expect(w.length, 30);
    expect(w.first, 700);
    expect(w.last, 990);
  });

  test('история короче окна — вся', () {
    final w = chatWindow<int>([1, 2, 3], limit: 30, floorTs: null, tsOf: ts);
    expect(w, [1, 2, 3]);
  });

  test('новое сообщение не сдвигает начало окна', () {
    final first = chatWindow<int>(all, limit: 30, floorTs: null, tsOf: ts);
    final more = [...all, 1000, 1010];
    final next = chatWindow<int>(more, limit: 30, floorTs: first.first, tsOf: ts);
    expect(next.first, first.first);
    expect(next.length, 32);
  });

  test('догрузка старых расширяет окно вверх', () {
    final w = chatWindow<int>(all, limit: 60, floorTs: 700, tsOf: ts);
    expect(w.length, 60);
    expect(w.first, 400);
  });

  test('граница старше всей истории — вся история', () {
    final w = chatWindow<int>(all, limit: 30, floorTs: -5, tsOf: ts);
    expect(w.length, 100);
  });
}
