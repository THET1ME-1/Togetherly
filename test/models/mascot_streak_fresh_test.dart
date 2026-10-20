import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot.dart';

/// Обращение 370 (20.10.2026): «маскот пишет, что серия прервана, на самом деле
/// мы заходили каждый день». У пары было три дня подряд, а «Серия прервана»
/// писал маскот, которого выбрали в тот же день: у каждого маскота своя серия,
/// и у нового она ещё не начиналась. Такому маскоту обрыв не пишем.
void main() {
  String day(int shift) {
    final d = DateTime.now().add(Duration(days: shift));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  final state = GroupMascotState(
    activeMascotId: 'feya',
    mascotStreaks: {
      'default_boy': {'s': 3, 'd': day(0)},
      'kolyuchka': {'s': 5, 'd': day(-4)},
      'empty': {'s': 0, 'd': day(0)},
    },
  );

  test('у нового маскота серия ещё не начиналась', () {
    expect(state.streakEverStarted('feya'), isFalse);
    expect(state.streakEverStarted('empty'), isFalse);
    expect(state.streakEverStarted(null), isFalse);
  });

  test('у маскота с серией — начиналась, даже если она оборвалась', () {
    expect(state.streakEverStarted('default_boy'), isTrue);
    expect(state.streakEverStarted('kolyuchka'), isTrue);
    expect(state.streakFor('kolyuchka'), 0, reason: 'оборвалась');
  });

  test('плашка галереи пишет обрыв только у маскота с прежней серией', () {
    final source = File('lib/screens/mascot_gallery_screen.dart').readAsStringSync();
    expect(source, contains('streakEverStarted('));
    expect(source, contains('s.streakNew'));
  });
}
