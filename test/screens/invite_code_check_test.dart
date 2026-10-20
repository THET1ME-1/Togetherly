import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/screens/invite_partner_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Код приглашения очень долго грузит и не делается» (обращение 376,
/// 20.10.2026, Android, снимок экрана «Позовите свою половинку» с «Готовим
/// код» и серыми кнопками).
///
/// Экран раздаёт только код, который сервер выдал или подтвердил в этом
/// запуске (правило 23.09.2026, `ConfirmedInviteCodes`). После перезапуска
/// приложения код из памяти телефона надо сверить заново, а экран приглашения
/// сверял его только на вкладке «Связь». С карточки «Позвать» на главной
/// человек видел крутилку без конца. И если сервер не отвечал, крутилка тоже
/// не кончалась: повторить было нечем.
class _FakePair extends PairData {
  _FakePair({
    String code = '',
    this.sessionLost = false,
    bool confirmed = false,
    List<String?>? answers,
  })  : _code = code,
        _confirmed = confirmed,
        _answers = answers ?? [];

  String _code;
  bool _confirmed;
  final bool sessionLost;

  /// Ответы сервера по очереди: код — сервер его выдал или подтвердил,
  /// `null` — сервер промолчал.
  final List<String?> _answers;

  int ensureCalls = 0;
  int regenerateCalls = 0;

  /// Запрос повис: сеть не ответила и не оборвалась. Код приходит, когда
  /// тест сам позовёт [arrive].
  bool hang = false;
  final _hung = Completer<void>();

  void arrive(String code) {
    _code = code;
    _confirmed = true;
    notifyListeners();
    _hung.complete();
  }

  @override
  bool get isPaired => false;

  @override
  String get inviteCode => _code;

  @override
  InviteCodeState get inviteCodeState {
    if (sessionLost) return InviteCodeState.sessionLost;
    if (_code.isEmpty || !_confirmed) return InviteCodeState.pending;
    return InviteCodeState.ready;
  }

  @override
  String get shareableInviteCode =>
      inviteCodeState == InviteCodeState.ready ? _code : '';

  void _answer() {
    final next = _answers.isEmpty ? null : _answers.removeAt(0);
    if (next != null) {
      _code = next;
      _confirmed = true;
    }
    notifyListeners();
  }

  @override
  Future<void> ensureInviteCodeIsReal() async {
    ensureCalls++;
    _answer();
  }

  @override
  Future<void> regenerateCode() async {
    regenerateCalls++;
    if (hang) return _hung.future;
    _answer();
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
    await tester.pump();
  }

  testWidgets('код из памяти телефона сверяется с сервером и появляется',
      (tester) async {
    final pair = _FakePair(code: 'AB12CD', answers: ['AB12CD']);
    await open(tester, pair);

    expect(pair.ensureCalls, 1,
        reason: 'после перезапуска сервер код ещё не подтверждал');
    expect(pair.regenerateCalls, 0,
        reason: 'живой код перевыпускать незачем: его могли уже отправить');
    expect(find.text('AB12CD'), findsOneWidget);
    expect(find.text(s().inviteCodeLoading), findsNothing);
  });

  testWidgets('сервер молчит: вместо вечной крутилки объяснение и «Ещё раз»',
      (tester) async {
    final pair = _FakePair(code: 'AB12CD', answers: [null, 'AB12CD']);
    await open(tester, pair);

    expect(find.text(s().inviteCodeLoading), findsNothing);
    expect(find.text(s().serverNotResponding), findsOneWidget);

    await tester.tap(find.text(s().retry));
    await tester.pump();
    await tester.pump();

    expect(pair.ensureCalls, 2);
    expect(find.text('AB12CD'), findsOneWidget);
    expect(find.text(s().serverNotResponding), findsNothing);
  });

  testWidgets('кода нет, сервер молчит: «Ещё раз» выпускает код заново',
      (tester) async {
    final pair = _FakePair(answers: [null, 'XY99ZZ']);
    await open(tester, pair);

    expect(pair.regenerateCalls, 1);
    expect(find.text(s().serverNotResponding), findsOneWidget);

    await tester.tap(find.text(s().retry));
    await tester.pump();
    await tester.pump();

    expect(pair.regenerateCalls, 2);
    expect(find.text('XY99ZZ'), findsOneWidget);
  });

  testWidgets('запрос повис: через 20 секунд «Ещё раз», поздний код встаёт сам',
      (tester) async {
    // У клиента сервера сроков нет: на повисшем соединении (VPN, плохая
    // сеть) выпуск кода не кончается вовсе, и крутилка стояла бы вечно.
    final pair = _FakePair()..hang = true;
    await open(tester, pair);

    expect(find.text(s().inviteCodeLoading), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    expect(find.text(s().serverNotResponding), findsOneWidget);
    expect(find.text(s().retry), findsOneWidget);

    pair.arrive('LATE01');
    await tester.pump();
    expect(find.text('LATE01'), findsOneWidget,
        reason: 'ответ пришёл позже срока, но код на сервере есть');
  });

  testWidgets('код, подтверждённый в этом запуске, заново не сверяется',
      (tester) async {
    // Лишняя сверка — это запрос к серверу и полный проход главной по
    // `notifyListeners` модели пары.
    final pair = _FakePair(code: 'AB12CD', confirmed: true);
    await open(tester, pair);

    expect(pair.ensureCalls + pair.regenerateCalls, 0);
    expect(find.text('AB12CD'), findsOneWidget);
  });

  testWidgets('два касания «Ещё раз» подряд запускают одну сверку',
      (tester) async {
    final pair = _FakePair(answers: [null]);
    await open(tester, pair);
    expect(pair.regenerateCalls, 1);

    pair.hang = true;
    // Между касаниями кадра нет: кнопка ещё на месте.
    await tester.tap(find.text(s().retry));
    await tester.tap(find.text(s().retry));
    expect(pair.regenerateCalls, 2,
        reason: 'второе касание пришло, пока первая сверка идёт');

    pair.arrive('AB12CD');
    await tester.pump();
  });

  testWidgets('надписи карточки читаются во всех палитрах', (tester) async {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    Color on(Color text, Color card) => Color.alphaBlend(text, card);

    for (var i = 0; i < kPalettes.length; i++) {
      for (final mode in Brightness.values) {
        final theme = buildAppTheme(kPalettes[i], mode);
        final name = '${kPalettes[i].name}, $mode';

        final failed = _FakePair(answers: [null]);
        await tester.pumpWidget(MaterialApp(
          home: InvitePartnerScreen(pairData: failed, theme: theme),
        ));
        await tester.pump();
        await tester.pump();
        final message = find.text(s().serverNotResponding);
        final card = tester
            .widget<Material>(find
                .ancestor(of: message, matching: find.byType(Material))
                .first)
            .color!;
        final text = tester.widget<Text>(message).style!.color!;
        expect(contrast(on(text, card), card), greaterThanOrEqualTo(4.5),
            reason: '$name: объяснение, почему кода нет');

        final ready = _FakePair(code: 'AB12CD', confirmed: true);
        await tester.pumpWidget(MaterialApp(
          home: InvitePartnerScreen(pairData: ready, theme: theme),
        ));
        await tester.pump();
        final code = tester.widget<Text>(find.text('AB12CD')).style!.color!;
        expect(contrast(on(code, card), card), greaterThanOrEqualTo(4.5),
            reason: '$name: сам код, его диктуют и переписывают');
      }
    }
  });

  testWidgets('на 320 точках при шрифте 1,3 код стоит в одну строку',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: TextScaler.linear(1.3),
        ),
        child: InvitePartnerScreen(
          pairData: _FakePair(code: 'AB12CD', confirmed: true),
          theme: AppThemes.pink,
        ),
      ),
    ));
    await tester.pump();

    final text = tester.renderObject<RenderParagraph>(find.text('AB12CD'));
    final lines = text
        .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 6))
        .map((b) => b.top.round())
        .toSet();
    expect(lines, hasLength(1),
        reason: 'код рвался на «AB12C» и «D», а его диктуют и переписывают');
  });

  testWidgets('без сессии экран говорит войти заново, а не крутится',
      (tester) async {
    final pair = _FakePair(code: 'AB12CD', sessionLost: true);
    await open(tester, pair);

    expect(find.text(s().inviteSessionLost), findsOneWidget);
    expect(find.text(s().inviteCodeLoading), findsNothing);
    expect(pair.ensureCalls + pair.regenerateCalls, 0,
        reason: 'без сессии сервер нас не узнаёт, спрашивать его нечем');
  });
}
