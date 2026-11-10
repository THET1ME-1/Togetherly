// Вход без писем: лист «Вернём доступ», ввод кода, новый пароль, лист с кодом
// у партнёра и экран «Способы входа». Узкие телефоны, крупный шрифт, обе
// темы — без переполнений и без кнопок в две строки.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/login_methods.dart';
import 'package:love_app/models/partner_reset.dart';
import 'package:love_app/screens/auth/forgot_password_sheet.dart';
import 'package:love_app/screens/auth/new_password_screen.dart';
import 'package:love_app/screens/auth/partner_code_screen.dart';
import 'package:love_app/screens/settings/login_methods_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/auth/ink.dart';
import 'package:love_app/widgets/auth/login_nudge.dart';
import 'package:love_app/widgets/auth/partner_reset_sheet.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  ColorScheme scheme(Brightness b) =>
      ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B), brightness: b);

  Future<void> pump(
    WidgetTester t,
    Widget child, {
    required double width,
    required Brightness b,
    double scale = 1.3,
    double height = 760,
  }) async {
    t.view.physicalSize = Size(width * 3, height * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final cs = scheme(b);
    await t.pumpWidget(
      MaterialApp(
        theme: ProfileTheme.data(cs),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
          ),
          child: child,
        ),
      ),
    );
    await t.pump();
  }

  /// Подпись кнопки целиком в одну строку: не перенесена и не обрезана.
  void oneLine(WidgetTester t, String label) {
    final box = t.renderObject<RenderBox>(find.text(label));
    final style = DefaultTextStyle.of(t.element(find.text(label))).style;
    expect(box.size.height, lessThan((style.fontSize ?? 14) * 2.2),
        reason: '«$label» в две строки');
    expect(
      box.size.width,
      greaterThanOrEqualTo(box.getMaxIntrinsicWidth(double.infinity) - 0.5),
      reason: '«$label» обрезана',
    );
  }

  test('розовое на бледно-розовом в теме гостя заменяется тёмным', () {
    const container = Color(0xFFFEEAF1);
    const pink = Color(0xFFFF7E8B);
    const dark = Color(0xFF22191A);
    expect(inkOn(container, pink, dark), dark);
    expect(inkOn(container, const Color(0xFF723339), dark), const Color(0xFF723339));
  });

  group('подсказка на главной', () {
    final now = DateTime.utc(2026, 11, 5, 12);
    const onlyPassword = LoginMethods(password: true, providers: {});
    test('только пароль, вторые сутки — показываем', () {
      expect(
        loginNudgeWanted(
          methods: onlyPassword,
          created: now.subtract(const Duration(days: 2)),
          now: now,
          dismissed: false,
        ),
        isTrue,
      );
    });
    test('в первые сутки после регистрации — молчим', () {
      expect(
        loginNudgeWanted(
          methods: onlyPassword,
          created: now.subtract(const Duration(hours: 5)),
          now: now,
          dismissed: false,
        ),
        isFalse,
      );
    });
    test('Google уже привязан или крестик нажат — молчим', () {
      expect(
        loginNudgeWanted(
          methods: const LoginMethods(password: true, providers: {'google'}),
          created: now.subtract(const Duration(days: 9)),
          now: now,
          dismissed: false,
        ),
        isFalse,
      );
      expect(
        loginNudgeWanted(
          methods: onlyPassword,
          created: now.subtract(const Duration(days: 9)),
          now: now,
          dismissed: true,
        ),
        isFalse,
      );
    });
  });

  for (final width in [320.0, 360.0]) {
    for (final b in Brightness.values) {
      final tag = '${width.toInt()} dp, ${b.name}';

      testWidgets('лист «Вернём доступ»: $tag', (t) async {
        ForgotWay? picked;
        await pump(
          t,
          Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () async => picked = await showForgotPasswordSheet(
                    ctx,
                    email: 'dima.k@gmail.com',
                  ),
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
          width: width,
          b: b,
        );
        await t.tap(find.text('открыть'));
        await t.pumpAndSettle();
        expect(find.text('Через партнёра'), findsOneWidget);
        expect(find.text('Письмом на почту'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Через партнёра'));
        await t.pumpAndSettle();
        expect(picked, ForgotWay.partner);
      });

      testWidgets('ввод кода: $tag', (t) async {
        await pump(
          t,
          const PartnerCodeScreen(email: 'dima.k@gmail.com'),
          width: width,
          b: b,
        );
        expect(find.text('Попросите код у партнёра'), findsOneWidget);
        await t.enterText(find.byType(TextField), '48291');
        await t.pump();
        expect(find.text('4'), findsOneWidget);
        final next = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Дальше'),
        );
        expect(next.onPressed, isNull, reason: 'пять цифр — рано');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('новый пароль: $tag', (t) async {
        await pump(
          t,
          const NewPasswordScreen(
            ticket: PartnerResetTicket(
              ticket: 't',
              name: 'Дима',
              partnerName: 'Маша',
              partnerFemale: true,
            ),
          ),
          width: width,
          b: b,
        );
        expect(find.text('Маша подтвердила, что это вы'), findsOneWidget);
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), '12345678');
        await t.enterText(fields.at(1), '12345679');
        await t.tap(find.text('Сохранить и войти'));
        await t.pump();
        expect(find.text('Пароли не совпадают'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('лист с кодом у партнёра: $tag', (t) async {
        final at = DateTime.utc(2026, 11, 5, 9, 40);
        await pump(
          t,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PartnerResetSheet(
                pending: PendingReset(
                  uid: 'u',
                  name: 'Дима',
                  female: true,
                  code: '482913',
                  at: at,
                  expiresAt: at.add(const Duration(minutes: 10)),
                ),
                clock: () => at.add(const Duration(seconds: 36)),
              ),
            ),
          ),
          width: width,
          b: b,
        );
        expect(find.text('482 913'), findsOneWidget);
        expect(find.text('Дима забыла пароль'), findsOneWidget);
        expect(find.text('Код действует ещё 9:24'), findsOneWidget);
        oneLine(t, 'Это не она');
        oneLine(t, 'Скопировать');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('лист хозяину «Ваш пароль меняют»: $tag', (t) async {
        final at = DateTime.utc(2026, 11, 10, 9, 40);
        var cancelled = 0;
        await pump(
          t,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: OwnResetSheet(
                own: OwnReset(
                  codeEntered: false,
                  partnerName: 'Константин',
                  at: at,
                  expiresAt: at.add(const Duration(minutes: 10)),
                ),
                clock: () => at.add(const Duration(seconds: 36)),
                onCancel: () async => cancelled++,
              ),
            ),
          ),
          width: width,
          b: b,
        );
        expect(find.text('Ваш пароль меняют'), findsOneWidget);
        expect(find.textContaining('Константин'), findsOneWidget);
        // Сам код хозяину не показывают: он только у партнёра.
        expect(find.textContaining(RegExp(r'\d{3} \d{3}')), findsNothing);
        oneLine(t, 'Это я');
        oneLine(t, 'Это не я');
        expect(t.takeException(), isNull);

        await t.tap(find.text('Это не я'));
        await t.pump();
        expect(cancelled, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });

      for (final ios in [false, true]) {
        testWidgets(
          'способы входа (${ios ? 'iPhone' : 'Android'}): $tag',
          (t) async {
            await pump(
              t,
              LoginMethodsScreen(
                scheme: scheme(b),
                onChangePassword: () {},
                ios: ios,
                initial: const LoginMethods(
                  password: true,
                  providers: {},
                  email: 'dima.k@gmail.com',
                ),
              ),
              width: width,
              b: b,
            );
            expect(find.text(ios ? '1/4' : '1/3'), findsOneWidget);
            expect(find.text('Google'), findsOneWidget);
            expect(find.text('Яндекс ID'), findsOneWidget);
            expect(find.text('Apple'), ios ? findsOneWidget : findsNothing);
            expect(find.text('Привязать'), findsNWidgets(ios ? 3 : 2));
            // Google и Яндекс всегда парой в одной строке; на Android пароль
            // над ними во всю ширину, на iPhone — в паре с Google.
            final google = t.getRect(find.text('Google'));
            final yandex = t.getRect(find.text('Яндекс ID'));
            final password = t.getRect(find.text('Пароль'));
            if (ios) {
              expect(password.top, closeTo(google.top, 1));
            } else {
              expect(google.top, closeTo(yandex.top, 1));
              expect(password.top, lessThan(google.top - 50));
            }
            expect(find.textContaining('только одним способом'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('два способа — спокойная плашка', (t) async {
    await pump(
      t,
      LoginMethodsScreen(
        scheme: scheme(Brightness.light),
        onChangePassword: () {},
        ios: false,
        initial: const LoginMethods(password: false, providers: {'google', 'yandex'}),
      ),
      width: 360,
      b: Brightness.light,
    );
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('Задать'), findsOneWidget);
    expect(find.text('Привязан'), findsNWidgets(2));
    expect(find.textContaining('Аккаунт один'), findsOneWidget);
  });
}
