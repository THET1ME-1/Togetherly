import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TOG-10: подарок дошёл до сервера, а парень его не увидел. Карточка
/// пришедшего подарка стояла над лентой воспоминаний, то есть почти в самом
/// низу главной, и показывала только первый подарок списка: незнакомый
/// сборке прятал её целиком. Правило отбора — `shownIncomingGifts`, здесь —
/// что главная им пользуется и держит карточку под сундуком.
void main() {
  final src = File('lib/screens/home_screen.dart').readAsStringSync();

  String body(String signature, [int length = 1600]) {
    final at = src.indexOf(signature);
    expect(at, greaterThan(0), reason: 'нет $signature');
    return src.substring(at, (at + length).clamp(0, src.length));
  }

  test('карточка и автопоказ берут подарки через shownIncomingGifts', () {
    expect(body('Widget _incomingGiftEntry()', 400), contains('shownIncomingGifts('));
    expect(body('Future<void> _onGiftEvent()', 500), contains('shownIncomingGifts('));
    expect(src.contains('_incomingGifts.first'), isFalse,
        reason: 'первый подарок списка может быть незнакомым и спрячет остальные');
  });

  test('события дня едут с сундуком, а не с лентой', () {
    final blocks = body('List<Widget> _buildHomeBlocks()', 9000);
    expect(blocks, contains('if (b == HomeBlock.chest) ...events()'));
    expect(blocks.contains('if (b == HomeBlock.lane) ...events()'), isFalse,
        reason: 'над лентой карточку подарка не видно: это низ главной');
  });

  test('без сундука события встают первыми', () {
    final blocks = body('List<Widget> _buildHomeBlocks()', 9000);
    final ret = blocks.indexOf('return [');
    expect(ret, greaterThan(0));
    final head = blocks.substring(ret, ret + 400);
    expect(head, contains('!shown.contains(HomeBlock.chest)'));
    final events = head.indexOf('events()');
    expect(events, greaterThan(0), reason: 'без сундука события дня некуда прицепить');
    expect(events, lessThan(head.indexOf('promptBlock()')), reason: 'подарок важнее подсказки');
  });
}
