import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/wallet_wait_screen.dart' show groupDigits;
import 'package:love_app/services/wallet_teaser.dart';

/// Конфиг Togetherly Wallet приезжает с сервера полем `app_config.wallet` и от
/// него зависит, куда ведёт кнопка на главной: на стену ожидания или в Wallet.
void main() {
  group('Конфиг Wallet', () {
    test('Пустое и сломанное значение означает «ещё не вышел»', () {
      for (final raw in [null, '', 'не json', 42, <String, Object>{}]) {
        final l = WalletLinks.fromJson(raw);
        expect(l.releasedFor(isIOS: false), isFalse, reason: '$raw');
        expect(l.releasedFor(isIOS: true), isFalse, reason: '$raw');
        expect(l.package, 'com.togetherly.money');
      }
    });

    test('Платформы открываются по отдельности', () {
      final l = WalletLinks.fromJson({'android': true, 'ios': false});
      expect(l.releasedFor(isIOS: false), isTrue);
      expect(l.releasedFor(isIOS: true), isFalse,
          reason: 'App Store может задержать сборку, iPhone ждёт на стене');
    });

    test('Строка JSON из настроек устройства читается так же, как карта', () {
      final l = WalletLinks.fromJson(
          '{"android":true,"rustore":"https://rustore.example/w"}');
      expect(l.android, isTrue);
      expect(l.rustore, 'https://rustore.example/w');
      final back = WalletLinks.fromJson(l.toJson());
      expect(back.toJson(), l.toJson());
    });

    test('Ссылка на магазин берётся по сборке Togetherly', () {
      final l = WalletLinks.fromJson({
        'play': 'P',
        'rustore': 'R',
        'github': 'G',
        'appstore': 'A',
      });
      expect(l.storeUrl(isIOS: false, store: 'play'), 'P');
      expect(l.storeUrl(isIOS: false, store: 'rustore'), 'R');
      expect(l.storeUrl(isIOS: false, store: 'github'), 'G');
      expect(l.storeUrl(isIOS: true, store: 'appstore'), 'A');
    });

    test('Без своей ссылки RuStore и GitHub уходят в Google Play', () {
      final l = WalletLinks.fromJson({'play': 'P'});
      expect(l.storeUrl(isIOS: false, store: 'rustore'), 'P');
      expect(l.storeUrl(isIOS: false, store: 'github'), 'P');
    });

    test('Ответ очереди разбирается с числами любого вида', () {
      final s = WaitlistState.fromJson({
        'count': 2418.0,
        'joined': true,
        'place': '2419',
        'wallet': {'ios': true},
      });
      expect(s.count, 2418);
      expect(s.joined, isTrue);
      expect(s.place, 2419);
      expect(s.links.ios, isTrue);
    });
  });

  test('Разряды числа разделены неразрывным пробелом', () {
    expect(groupDigits(7), '7');
    expect(groupDigits(2418), '2\u00A0418');
    expect(groupDigits(100000), '100\u00A0000');
    expect(groupDigits(1234567), '1\u00A0234\u00A0567');
  });
}
