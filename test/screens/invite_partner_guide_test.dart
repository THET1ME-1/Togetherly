import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/screens/invite_partner_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Владелец 12.11.2026, снимки нового пустого аккаунта: «Тут совершенно
/// никаких подсказок с маскотом нет… люди не знают, как и куда вписывать
/// код». И следом: «нельзя код сменить».
///
/// На экране «Позовите свою половинку» Ту сперва показывает на код (его
/// отправляют партнёру), потом на «Ввести код» (сюда вписывают код партнёра).
/// Каждая подсказка одноразовая. Под карточкой кода есть «Новый код».
class _FakePair extends PairData {
  _FakePair(this._code);

  String _code;
  int regenerateCalls = 0;

  @override
  bool get isPaired => false;

  @override
  String get inviteCode => _code;

  @override
  InviteCodeState get inviteCodeState =>
      _code.isEmpty ? InviteCodeState.pending : InviteCodeState.ready;

  @override
  String get shareableInviteCode => _code;

  @override
  Future<void> ensureInviteCodeIsReal() async {}

  @override
  Future<void> regenerateCode() async {
    regenerateCalls++;
    _code = 'NEW${regenerateCalls}XY';
    notifyListeners();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  AppStrings s() => LocaleService.current;

  Future<void> open(WidgetTester tester, PairData pair) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: InvitePartnerScreen(pairData: pair, theme: AppThemes.pink),
    ));
    await tester.pump();
  }

  Future<void> wait(WidgetTester tester, Duration d) async {
    for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Ту по очереди показывает, куда отправить код и куда вписать чужой', (tester) async {
    await open(tester, _FakePair('LAS9X5'));
    expect(find.text(s().inviteCodeHint), findsNothing, reason: 'подсказка не должна вылезать в первый же кадр');

    await wait(tester, const Duration(seconds: 2));
    expect(find.text(s().inviteCodeHint), findsOneWidget, reason: 'Ту не показал, что код отправляют партнёру');
    expect(find.text(s().inviteEnterHint), findsNothing, reason: 'две подсказки разом — это завал');

    await tester.tap(find.text(s().gotIt));
    await wait(tester, const Duration(seconds: 2));
    expect(find.text(s().inviteCodeHint), findsNothing);
    expect(find.text(s().inviteEnterHint), findsOneWidget, reason: 'Ту не показал, куда вписать код партнёра');

    await tester.tap(find.text(s().gotIt));
    await wait(tester, const Duration(seconds: 1));

    // Второй заход: подсказки уже видели.
    await tester.pumpWidget(const SizedBox());
    await open(tester, _FakePair('LAS9X5'));
    await wait(tester, const Duration(seconds: 3));
    expect(find.text(s().inviteCodeHint), findsNothing, reason: 'подсказка не одноразовая');
    expect(find.text(s().inviteEnterHint), findsNothing, reason: 'подсказка не одноразовая');
    await tester.pumpWidget(const SizedBox());
    await wait(tester, const Duration(seconds: 13));
  });

  testWidgets('«Новый код» выпускает другой код', (tester) async {
    final pair = _FakePair('LAS9X5');
    await open(tester, pair);
    expect(find.text('LAS9X5'), findsOneWidget);

    await tester.tap(find.text(s().newInviteCode));
    await wait(tester, const Duration(milliseconds: 500));
    expect(pair.regenerateCalls, 1);
    expect(find.text('NEW1XY'), findsOneWidget, reason: 'на экране остался прежний код');
    expect(find.text(s().newCodeGenerated), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await wait(tester, const Duration(seconds: 13));
  });
}
