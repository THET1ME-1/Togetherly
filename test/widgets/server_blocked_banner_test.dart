// TOG-16: человек уже в приложении, а наш сервер в его сети закрыт. Он видит
// «Не сохранилось», вечную загрузку и счётчик «Скучаю», который откатывается,
// и пишет в поддержку, что всё сломалось. Плашка поверх экранов говорит, в чём
// дело и что поможет; нажатие проверяет связь заново.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/network/server_reach.dart';
import 'package:love_app/widgets/offline_sync_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Язык меняется сразу, запись выбора в настройки идёт следом. Ждать её внутри
/// testWidgets нельзя: без живых настроек ожидание не кончается.
void _language(AppLanguage lang) =>
    LocaleService.instance.setLanguage(lang).ignore();

Widget _app({double textScale = 1.0}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: OfflineSyncBanner(child: const Scaffold(body: SizedBox.expand())),
    );

void main() {
  late bool oursAnswers;
  late int checks;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    oursAnswers = false;
    checks = 0;
    ServerReach.instance = ServerReach(
      probeOurs: () async {
        checks++;
        return oursAnswers;
      },
      probeInternet: () async => true,
    );
  });

  tearDown(() => _language(AppLanguage.ru));

  testWidgets('сервер закрыт в сети — плашка советует VPN', (tester) async {
    _language(AppLanguage.ru);
    ServerReach.instance.state.value = ServerReachState.blocked;
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(trKey('serverBlockedChip')), findsOneWidget);
  });

  testWidgets('сервер отвечает — плашки нет', (tester) async {
    _language(AppLanguage.ru);
    ServerReach.instance.state.value = ServerReachState.ok;
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(trKey('serverBlockedChip')), findsNothing);
  });

  // На эмуляторе плашка легла поверх кнопки «назад» экрана регистрации и
  // забирала нажатие: уйти с экрана, пока сервер закрыт, было нельзя.
  testWidgets('плашка не перехватывает нажатия: кнопка под ней работает',
      (tester) async {
    _language(AppLanguage.ru);
    ServerReach.instance.state.value = ServerReachState.blocked;
    var backTapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: OfflineSyncBanner(
        child: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 400,
                height: 60,
                child: TextButton(
                  onPressed: () => backTapped++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tapAt(tester.getCenter(find.text(trKey('serverBlockedChip'))));
    await tester.pump();

    expect(backTapped, 1);
    expect(checks, 0, reason: 'связь перепроверяют сами запросы, а не палец');
  });

  testWidgets('сервер ответил — плашка уходит сама', (tester) async {
    _language(AppLanguage.ru);
    ServerReach.instance.state.value = ServerReachState.blocked;
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 300));

    ServerReach.instance.reached();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(trKey('serverBlockedChip')), findsNothing);
  });

  testWidgets('нет ни сервера, ни чужих сайтов — плашка «нет сети»',
      (tester) async {
    _language(AppLanguage.ru);
    ServerReach.instance.state.value = ServerReachState.offline;
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Нет сети'), findsOneWidget);
    expect(find.text(trKey('serverBlockedChip')), findsNothing);
  });

  testWidgets('320 точек и шрифт 1.3: плашка помещается на каждом языке',
      (tester) async {
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final lang in AppLanguage.values) {
      _language(lang);
      ServerReach.instance.state.value = ServerReachState.blocked;
      await tester.pumpWidget(_app(textScale: 1.3));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: lang.code);
      final chip = find.text(trKey('serverBlockedChip'));
      expect(chip, findsOneWidget, reason: lang.code);
      final rect = tester.getRect(chip);
      expect(rect.left, greaterThanOrEqualTo(0), reason: lang.code);
      expect(rect.right, lessThanOrEqualTo(320), reason: lang.code);

      ServerReach.instance.state.value = ServerReachState.unknown;
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
