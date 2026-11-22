import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/support_link.dart';

void main() {
  group('ссылка в бота поддержки', () {
    test('полный контекст как в примере службы', () {
      expect(
        supportStartPayload(
          app: 'tg',
          version: '1.44.0',
          build: '272',
          platform: 'ios',
          device: 'iPhone15,3',
          uid: 'abc123def456ghi',
        ),
        'tg_1-44-0-272_i_iPhone15-3_abc123def456ghi',
      );
    });

    test('пустые части — x', () {
      expect(
        supportStartPayload(app: 'tg', version: '1.44.0', build: '', platform: 'android'),
        'tg_1-44-0_a_x_x',
      );
    });

    test('длинная модель режется до 20 знаков', () {
      final payload = supportStartPayload(
        app: 'tg',
        version: '1.44.0',
        build: '272',
        platform: 'android',
        device: 'Some Very Long Device Model Name 2026 Pro Max',
        uid: 'u1',
      );
      expect(payload.split('_')[3], 'Some-Very-Long-Devic');
    });

    test('за 64 знака сначала уходит uid', () {
      final payload = supportStartPayload(
        app: 'tg',
        version: '1.44.0',
        build: '272',
        platform: 'android',
        device: 'SM-S918BSM-S918BSM-S',
        uid: 'abcdefghijklmnopqrstuvwxyz1234',
      );
      expect(payload.length, lessThanOrEqualTo(64));
      expect(payload.endsWith('_x'), isTrue);
    });

    test('только разрешённые Telegram знаки', () {
      final payload = supportStartPayload(
        app: 'tg',
        version: '1.44.0',
        build: '272',
        platform: 'ios',
        device: 'iPad13,1 (Wi‑Fi)',
        uid: 'ab_c-d!',
      );
      expect(RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(payload), isTrue);
      expect(payload.split('_').length, 5);
    });

    test('ссылка открывает бота с payload', () {
      expect(
        supportBotUri('tg_1-44-0_a_x_x').toString(),
        'https://t.me/TogetherlyBugsBot?start=tg_1-44-0_a_x_x',
      );
    });
  });
}
