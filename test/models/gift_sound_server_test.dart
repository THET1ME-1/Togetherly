import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';

/// Сервер примет звук только у подарков из `SOUND_GIFTS` в `gifts.pb.js`:
/// разойдись таблицы — лист звука откроется, а подарок вернётся с bad_sound.
void main() {
  test('SOUND_GIFTS на сервере совпадает с carriesSound', () {
    final local = {
      for (final gift in [...GiftCatalog.all, ...GiftCatalog.chest])
        if (gift.carriesSound) gift.key,
    };
    final hook = File('pocketbase/pb_hooks/gifts.pb.js').readAsStringSync();
    final table = RegExp(r'const SOUND_GIFTS = \{([^}]*)\}').firstMatch(hook);
    expect(table, isNotNull, reason: 'в gifts.pb.js нет таблицы SOUND_GIFTS');
    final server = RegExp(r'(\w+)\s*:\s*true')
        .allMatches(table!.group(1)!)
        .map((m) => m.group(1))
        .toSet();
    expect(server, local);
  });
}
