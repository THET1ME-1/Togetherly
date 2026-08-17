import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/invite_code.dart';

/// Код приглашения диктуют голосом, пересылают ссылкой и набирают руками — и на
/// каждом из этих путей он приезжает не в том виде, в каком лежит на сервере.
/// Каждый такой случай раньше отвечал «Код не найден», хотя код был живой.
void main() {
  group('normalizeInviteCode', () {
    test('приводит регистр и снимает пробелы', () {
      expect(normalizeInviteCode('  avqvv3 '), 'AVQVV3');
    });

    test('достаёт код из пересланной ссылки', () {
      expect(
        normalizeInviteCode('https://togetherly.day/invite/HQ792S'),
        'HQ792S',
      );
    });

    // Приглашения выдаются со своим доменом с 17.08.2026, но ссылки со старым
    // именем разосланы людьми и живут в чужих переписках — их приложение
    // обязано понимать столько же, сколько живёт сам поддомен.
    test('понимает и старую ссылку с duckdns', () {
      expect(
        normalizeInviteCode('https://togetherly.duckdns.org/invite/HQ792S'),
        'HQ792S',
      );
    });

    test('достаёт код из ссылки приложения', () {
      expect(normalizeInviteCode('loveapp://invite/AB2C3D'), 'AB2C3D');
    });

    test('отбрасывает хвост запроса у ссылки', () {
      expect(
        normalizeInviteCode('https://togetherly.day/invite/XY45ZZ?utm=tg'),
        'XY45ZZ',
      );
    });

    test('снимает кавычку от автозамены', () {
      expect(normalizeInviteCode('‘AXBGH2'), 'AXBGH2');
    });

    test('переводит кириллицу в латиницу', () {
      expect(normalizeInviteCode('АВЕКМН'), 'ABEKMH');
    });

    test('выбрасывает дефисы и пробелы внутри', () {
      expect(normalizeInviteCode('AV-QV V3'), 'AVQVV3');
    });

    test('пустой ввод остаётся пустым', () {
      expect(normalizeInviteCode(null), '');
      expect(normalizeInviteCode('   '), '');
    });
  });
}
