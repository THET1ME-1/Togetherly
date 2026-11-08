import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Вход через Google и Apple без страницы в браузере (09.11.2026).
///
/// Страница Google рвалась: Google просил подтвердить личность ключом
/// доступа, человек уходил в другое приложение, Android закрывал соединение,
/// по которому PocketBase ждёт ответа, и страница отвечала «Auth failed».
/// Системный вход отдаёт токен прямо приложению, выход из него ничего не
/// ломает. Нативный вход Apple был написан раньше, но экраны звали
/// `signInWithOAuth2` напрямую и до него не доходили — поэтому развилка стоит
/// именно там.
void main() {
  final auth = File('lib/services/pb_auth_service.dart').readAsStringSync();

  test('кнопки входа идут через развилку с системным входом', () {
    final start = auth.indexOf('Future<RecordModel?> signInWithOAuth2(');
    final body = auth.substring(start, auth.indexOf('_runOAuth2(provider)', start));
    expect(body, contains('_trySystemSignIn(provider)'));
  });

  test('Google проверяется сервером, клиенты совпадают со службой проверки', () {
    expect(auth, contains("'/api/google/native'"));
    final relay = File('pocketbase/apns/apns_relay.py').readAsStringSync();
    final web = RegExp(r"_googleWebClientId =\s*'([^']+)'").firstMatch(auth)!.group(1)!;
    final ios = RegExp(r"_googleIosClientId =\s*'([^']+)'").firstMatch(auth)!.group(1)!;
    expect(relay, contains(web));
    expect(relay, contains(ios));
    // Окно Google на iPhone возвращается в приложение по своей схеме адреса.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('com.googleusercontent.apps.${ios.replaceAll('.apps.googleusercontent.com', '')}'));
    expect(File('pocketbase/pb_hooks/google_native.pb.js').existsSync(), isTrue);
  });
}
