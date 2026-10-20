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

  // Правило владельца (20.10.2026): «код должен крутиться, пока его не даст
  // сервер». Ни кода без подтверждения, ни таблички вместо крутилки: экран
  // сам переспрашивает сервер.

  testWidgets('сервер молчит: крутилка стоит, а сверка повторяется сама',
      (tester) async {
    final pair = _FakePair(code: 'AB12CD', answers: [null, 'AB12CD']);
    await open(tester, pair);

    expect(find.text(s().inviteCodeLoading), findsOneWidget);
    expect(find.text('AB12CD'), findsNothing,
        reason: 'код из памяти телефона сервер ещё не подтвердил');
    expect(find.text(s().retry), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    expect(pair.ensureCalls, 2);
    expect(find.text('AB12CD'), findsOneWidget);
    expect(find.text(s().inviteCodeLoading), findsNothing);
  });

  testWidgets('кода нет, сервер молчит: выпуск повторяется сам',
      (tester) async {
    final pair = _FakePair(answers: [null, 'XY99ZZ']);
    await open(tester, pair);

    expect(pair.regenerateCalls, 1);
    expect(find.text(s().inviteCodeLoading), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    expect(pair.regenerateCalls, 2);
    expect(find.text('XY99ZZ'), findsOneWidget);
  });

  testWidgets('пока сервер молчит, неподтверждённый код не появляется',
      (tester) async {
    final pair = _FakePair(code: 'AB12CD');
    await open(tester, pair);

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 31));
    }
    expect(pair.ensureCalls, greaterThan(3),
        reason: 'экран переспрашивает сервер, пока тот не ответит');
    expect(find.text('AB12CD'), findsNothing);
    expect(find.text(s().inviteCodeLoading), findsOneWidget);
  });

  testWidgets('запрос повис: через 20 секунд пробуем снова, поздний код встаёт',
      (tester) async {
    // У клиента сервера сроков нет: на повисшем соединении (VPN, плохая
    // сеть) выпуск кода не кончается вовсе, и новой попытки не было бы.
    final pair = _FakePair()..hang = true;
    await open(tester, pair);

    expect(find.text(s().inviteCodeLoading), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    await tester.pump(const Duration(seconds: 6));
    expect(pair.regenerateCalls, 2);
    expect(find.text(s().inviteCodeLoading), findsOneWidget);

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

  testWidgets('ушли с экрана — сверка больше не повторяется', (tester) async {
    final pair = _FakePair(code: 'AB12CD');
    await open(tester, pair);
    expect(pair.ensureCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(minutes: 2));
    expect(pair.ensureCalls, 1);
  });

  testWidgets('код читается во всех палитрах', (tester) async {
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

        final ready = _FakePair(code: 'AB12CD', confirmed: true);
        await tester.pumpWidget(MaterialApp(
          home: InvitePartnerScreen(pairData: ready, theme: theme),
        ));
        await tester.pump();
        final shown = find.text('AB12CD');
        final card = tester
            .widget<Material>(find
                .ancestor(of: shown, matching: find.byType(Material))
                .first)
            .color!;
        final code = tester.widget<Text>(shown).style!.color!;
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

  testWidgets('без сессии код тоже не показывается', (tester) async {
    final pair = _FakePair(code: 'AB12CD', sessionLost: true);
    await open(tester, pair);

    expect(find.text('AB12CD'), findsNothing);
    expect(find.text(s().inviteCodeLoading), findsOneWidget);
  });
}
