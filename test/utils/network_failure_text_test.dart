// TOG-16: отзыв из США (18.10.2026) — при создании аккаунта «почта не найдена»,
// вход через Google тоже с ошибкой; обращения из Украины 23.10 — «пишет, что
// нет интернета, когда он есть». Обрыв связи не должен звучать как ошибка в
// почте, а закрытый в сети сервер — как отсутствие интернета.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/network/server_reach.dart';
import 'package:love_app/utils/auth_failure.dart';
import 'package:love_app/utils/network_failure_text.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  test('обрыв и молчание — это сеть, а ответ сервера — нет', () {
    expect(AuthFailure.noConnection.isNetwork, isTrue);
    expect(AuthFailure.timeout.isNetwork, isTrue);
    expect(AuthFailure.badCredentials.isNetwork, isFalse);
    expect(AuthFailure.emailTaken.isNetwork, isFalse);
    expect(AuthFailure.serverDown.isNetwork, isFalse);
    // У сорванного шифрования свой текст, он уже советует VPN.
    expect(AuthFailure.blockedConnection.isNetwork, isFalse);
  });

  test('сервер закрыт в сети — прямой совет про VPN', () {
    final text = networkFailureText(ServerReachState.blocked);
    expect(text, contains('VPN'));
    expect(text.toLowerCase(), isNot(contains('email')));
    expect(text.toLowerCase(), isNot(contains('почт')));
  });

  test('интернета нет — так и сказано, без VPN', () {
    final text = networkFailureText(ServerReachState.offline);
    expect(text, trKey('noInternet'));
    expect(text, isNot(contains('VPN')));
  });

  test('сервер доступен — просим повторить, а не проверять интернет', () {
    for (final state in [ServerReachState.ok, ServerReachState.unknown]) {
      final text = networkFailureText(state);
      expect(text, trKey('serverSlowRetry'));
      expect(text.toLowerCase(), isNot(contains('интернет')));
    }
  });

  test('совет про VPN есть на каждом языке', () {
    for (final lang in AppLanguage.values) {
      for (final key in [
        'serverBlockedVpn',
        'serverBlockedChip',
        'noInternet',
        'serverSlowRetry',
      ]) {
        final text = kStrings[key]?[lang.code];
        expect(text, isNotNull, reason: '$key для ${lang.code}');
        expect(text!.trim(), isNotEmpty, reason: '$key для ${lang.code}');
      }
      expect(trDict('serverBlockedVpn', lang.code), contains('VPN'),
          reason: lang.code);
    }
  });
}
