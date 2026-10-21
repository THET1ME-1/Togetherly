import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/incoming_gifts.dart';

/// TOG-10: «отправила парню, а у него не появился». Главная брала первый
/// подарок списка, и подарок, которого сборка ещё не знает (сезонный до
/// приезда каталога), прятал карточку целиком вместе со всеми знакомыми.
void main() {
  Map<String, dynamic> g(String id, String key) => {'id': id, 'gift_key': key};

  test('незнакомый первым не прячет знакомые под ним', () {
    final shown = shownIncomingGifts([g('n1', 'gift_from_next_year'), g('r1', 'rose'), g('h1', 'heart')]);
    expect(shown.map((e) => e['id']), ['r1', 'h1']);
  });

  test('подарки сундука и отданная рамка показываются', () {
    final shown = shownIncomingGifts([g('p1', 'potion'), g('f1', 'frame_cat')]);
    expect(shown.map((e) => e['id']), ['p1', 'f1']);
  });

  test('порядок прежний: новые первыми', () {
    final shown = shownIncomingGifts([g('a', 'heart'), g('b', 'hug'), g('c', 'teddy')]);
    expect(shown.map((e) => e['id']), ['a', 'b', 'c']);
  });

  test('пустой ключ и пустой список', () {
    expect(shownIncomingGifts([g('x', '')]), isEmpty);
    expect(shownIncomingGifts(const []), isEmpty);
  });
}
