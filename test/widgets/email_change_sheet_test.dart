// Смена почты кодом из письма. «У меня не та почта» правили руками через
// суперюзера (обращения 148, 179, 208). Сервер проверен стендом на PB 0.39.4,
// здесь — разбор его ответов, лист и подключение.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/email_change_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/common/email_change_sheet.dart';

class _FakeService extends EmailChangeService {
  final requested = <String>[];
  String? lastCode;
  EmailChangeResult nextRequest = const EmailChangeResult.ok();

  @override
  Future<EmailChangeResult> requestCode(String email) async {
    requested.add(email);
    return nextRequest;
  }

  @override
  Future<EmailChangeResult> confirm(String email, String code) async {
    lastCode = code;
    return code == '123456'
        ? EmailChangeResult.ok(email: email, token: 't')
        : const EmailChangeResult.failed(EmailChangeError.wrong);
  }
}

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  test('ответы сервера разбираются в понятные отказы', () {
    expect(parseEmailChange(200, {'ok': true, 'email': 'a@b.c', 'token': 'x'}).email,
        'a@b.c');
    expect(parseEmailChange(409, {'code': 'taken'}).error, EmailChangeError.taken);
    final wait = parseEmailChange(429, {'code': 'wait', 'retryIn': 42});
    expect((wait.error, wait.retryIn), (EmailChangeError.wait, 42));
    expect(parseEmailChange(500, null).error, EmailChangeError.network);
    expect(parseEmailChange(400, {'code': 'чушь'}).error, EmailChangeError.network);
  });

  test('каждая фраза есть на семи языках', () {
    final keys = [
      'emailChangeTitle', 'emailChangeHint', 'emailChangeNewLabel',
      'emailChangeSend', 'emailChangeSentTo', 'emailChangeCodeLabel',
      'emailChangeConfirm', 'emailChangeResend', 'emailChangeResendIn',
      'emailChangeOther', 'emailChangeDone',
      for (final e in EmailChangeError.values) 'emailChangeErr.${e.name}',
    ];
    for (final key in keys) {
      for (final lang in ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de']) {
        expect(kStrings[key]?[lang], isNotNull, reason: '$key/$lang');
      }
    }
  });

  Future<(_FakeService, List<String?>)> open(WidgetTester tester) async {
    final fake = _FakeService();
    final results = <String?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(await showEmailChangeSheet(
                context,
                scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B)),
                service: fake,
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (fake, results);
  }

  testWidgets('адрес → код → почта сменена', (tester) async {
    final (fake, results) = await open(tester);
    await tester.enterText(find.byKey(const Key('email-change-email')), 'new@mail.com');
    await tester.tap(find.byKey(const Key('email-change-main')));
    await tester.pump();
    expect(fake.requested, ['new@mail.com']);
    expect(find.textContaining('Код отправлен на new@mail.com'), findsOneWidget);
    expect(find.text('Ещё раз через 60 с'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('email-change-code')), '000000');
    await tester.pump();
    expect(find.text('Код не подошёл'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('email-change-code')), '123456');
    await tester.pumpAndSettle();
    expect(results, ['new@mail.com']);
  });

  testWidgets('отказ сервера показан словами, лист остаётся', (tester) async {
    final (fake, results) = await open(tester);
    fake.nextRequest = const EmailChangeResult.failed(EmailChangeError.taken);
    await tester.enterText(find.byKey(const Key('email-change-email')), 'b@mail.com');
    await tester.tap(find.byKey(const Key('email-change-main')));
    await tester.pump();
    expect(find.text('Эта почта уже занята другим аккаунтом'), findsOneWidget);
    expect(find.byKey(const Key('email-change-code')), findsNothing);
    expect(results, isEmpty);
  });

  test('настройки и профиль подключены, хук закрыт входом', () {
    final settings = File('lib/screens/settings_screen.dart').readAsStringSync();
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final hook = File('pocketbase/pb_hooks/email_change.pb.js').readAsStringSync();
    expect(settings, contains("trKey('emailChangeTitle')"));
    expect(profile, contains('showEmailChangeSheet('));
    expect(profile, contains('widget.userData.setEmail(email)'));
    expect('\$apis.requireAuth("users")'.allMatches(hook).length, 2);
    expect(hook, contains('record.newAuthToken()'));
  });
}
