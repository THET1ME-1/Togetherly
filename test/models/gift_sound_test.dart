import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/models/partner_profile.dart';
import 'package:love_app/models/sound_clip.dart';
import 'package:love_app/services/gifts_service.dart';

/// Звук к подарку «Песня» (обращение 244): кусок песни или голос. Лежит в
/// полях `gifts.sound` (ссылка) и `gifts.sound_meta` (json с волной).
void main() {
  const meta =
      '{"ms":20000,"peaks":"1234567890123456789012345678901234567890","kind":"song","title":"Lovely Day","artist":"Bill Withers"}';

  test('звук читается из записи подарка', () {
    final clip = SoundClip.fromGiftRecord({
      'sound': 'pb://media/abcdefghij12345/sound.m4a',
      'sound_meta': meta,
    })!;
    expect(clip.url, 'pb://media/abcdefghij12345/sound.m4a');
    expect(clip.duration, const Duration(seconds: 20));
    expect(clip.kind, SoundKind.song);
    expect(clip.title, 'Lovely Day');
    expect(clip.artist, 'Bill Withers');
  });

  test('без ссылки звука нет, битый meta даёт звук без волны', () {
    expect(SoundClip.fromGiftRecord({'sound': '', 'sound_meta': meta}), isNull);
    expect(SoundClip.fromGiftRecord({'note': 'привет'}), isNull);
    final broken = SoundClip.fromGiftRecord(
        {'sound': 'pb://media/a/b.m4a', 'sound_meta': '{битый'})!;
    expect(broken.duration, Duration.zero);
    expect(broken.kind, SoundKind.voice);
    expect(broken.bars, hasLength(40));
  });

  test('в запрос звук уходит ссылкой и meta', () {
    const clip = SoundClip(
      url: 'pb://media/abcdefghij12345/sound.m4a',
      duration: Duration(milliseconds: 18000),
      peaks: '1234567890123456789012345678901234567890',
      kind: SoundKind.voice,
    );
    final fields = GiftsService.soundFields(clip);
    expect(fields['sound'], clip.url);
    final sent = jsonDecode(fields['soundMeta'] as String) as Map;
    expect(sent['ms'], 18000);
    expect(sent['kind'], 'voice');
    expect(sent['peaks'], clip.peaks);
    expect(sent.containsKey('url'), isFalse);
    expect(GiftsService.soundFields(null), isEmpty);
  });

  test('полка показывает звук, и подарок со звуком есть что открыть', () {
    final memo = memosOfKey([
      {
        'gift_key': 'song',
        'created': '2026-10-14 10:00:00.000Z',
        'sound': 'pb://media/abcdefghij12345/sound.m4a',
        'sound_meta': meta,
      },
    ], 'song').single;
    expect(memo.sound, isNotNull);
    expect(memo.sound!.title, 'Lovely Day');
    expect(memo.hasText, isTrue);
  });

  test('звук несёт только «Песня»', () {
    final local = {
      for (final gift in [...GiftCatalog.all, ...GiftCatalog.chest])
        if (gift.carriesSound) gift.key,
    };
    expect(local, {'song'});
  });
}
