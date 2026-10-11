import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';
import 'package:love_app/widgets/unfold/unfold_touch.dart';

const _screen = Size(360, 760);
const _window = ValueKey<String>('unfold-window');
const _button = ValueKey<String>('button');
const _buttonRect = Rect.fromLTWH(200, 500, 120, 48);

final _navigator = GlobalKey<NavigatorState>();

class _Second extends StatelessWidget {
  const _Second();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 80),
          const UnfoldStagger(index: 0, child: Text('первый блок')),
          const UnfoldStagger(index: 5, child: Text('шестой блок')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('назад'),
          ),
        ],
      ),
    );
  }
}

/// Первый экран: обычная кнопка, обычный `MaterialPageRoute`. Про переход
/// экран не знает ничего — в приложении таких мест больше сотни.
class _First extends StatefulWidget {
  const _First();

  @override
  State<_First> createState() => _FirstState();
}

class _FirstState extends State<_First> {
  bool buttonShown = true;

  void hideButton() => setState(() => buttonShown = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (buttonShown)
            Positioned.fromRect(
              rect: _buttonRect,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const _Second()),
                ),
                child: Container(
                  key: _button,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _fallback = FadeForwardsPageTransitionsBuilder();

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_screen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    navigatorKey: _navigator,
    theme: ThemeData(
      scaffoldBackgroundColor: const Color(0xFFF7F3F0),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android:
              UnfoldPageTransitionsBuilder(fallback: _fallback),
          TargetPlatform.iOS:
              UnfoldPageTransitionsBuilder(fallback: _fallback),
        },
      ),
    ),
    home: const _First(),
  ));
}

/// Нажатие и первый видимый кадр (самый первый кадр маршрута за сценой).
Future<void> _tapButton(WidgetTester tester) async {
  await tester.tap(find.byKey(_button));
  await tester.pump();
  await tester.pump();
}

double _opacityOf(WidgetTester tester, String text) => tester
    .widget<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first)
    .opacity;

Future<void> _backGesture(String method, [Map<String, Object?>? arguments]) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

void main() {
  setUp(() {
    UnfoldTouch.install();
    UnfoldTouch.forget();
    UnfoldPageTransitionsBuilder.enabled = true;
  });

  testWidgets('обычный экран вырастает из нажатой кнопки', (tester) async {
    await _pumpApp(tester);
    expect(tester.getRect(find.byKey(_button)), _buttonRect);

    await _tapButton(tester);
    expect(tester.getRect(find.byKey(_window)), _buttonRect,
        reason: 'первый кадр обязан совпасть с кнопкой, иначе виден скачок');
    final clip = tester.widget<ClipRRect>(find.byKey(_window));
    expect(clip.borderRadius, BorderRadius.circular(16),
        reason: 'окно начинается со скругления самой кнопки');

    await tester.pump(const Duration(milliseconds: 60));
    final growing = tester.getRect(find.byKey(_window));
    expect(growing.width, greaterThan(_buttonRect.width));
    expect(growing.width, lessThan(_screen.width));

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_window)), Offset.zero & _screen);
    expect(find.text('первый блок'), findsOneWidget);
  });

  testWidgets('окно залито цветом экрана, а не кнопки', (tester) async {
    await _pumpApp(tester);
    await _tapButton(tester);

    final tint = tester.widget<ColoredBox>(find
        .descendant(of: find.byKey(_window), matching: find.byType(ColoredBox))
        .last);
    expect(tint.color, const Color(0xFFF7F3F0));
  });

  testWidgets('чёрный экран называет свой цвет окна сам', (tester) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF7F3F0),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android:
              UnfoldPageTransitionsBuilder(fallback: _fallback),
        }),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const UnfoldTint(
                    color: Colors.black,
                    child: Scaffold(backgroundColor: Colors.black),
                  ),
                ),
              ),
              child: Container(
                  key: _button, width: 120, height: 48, color: Colors.teal),
            ),
          ),
        ),
      ),
    ));
    await _tapButton(tester);

    final tint = tester.widget<ColoredBox>(find
        .descendant(of: find.byKey(_window), matching: find.byType(ColoredBox))
        .last);
    expect(tint.color, Colors.black,
        reason: 'светлая заливка под чёрным плеером дала бы вспышку');
    await tester.pumpAndSettle();
  });

  testWidgets('блоки экрана проявляются по очереди', (tester) async {
    await _pumpApp(tester);
    await _tapButton(tester);
    await tester.pump(const Duration(milliseconds: 140));

    expect(_opacityOf(tester, 'первый блок'), greaterThan(0.2));
    expect(_opacityOf(tester, 'шестой блок'), 0);
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'шестой блок'), 1);
  });

  testWidgets('экран, открытый не касанием, идёт штатным переходом',
      (tester) async {
    await _pumpApp(tester);
    _navigator.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const _Second()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byKey(_window), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('первый блок'), findsOneWidget);
  });

  testWidgets('«назад» складывает экран обратно в кнопку', (tester) async {
    await _pumpApp(tester);
    await _tapButton(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('назад'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final folding = tester.getRect(find.byKey(_window));
    expect(folding.width, lessThan(_screen.width));
    expect(folding.width, greaterThan(_buttonRect.width));

    await tester.pump(const Duration(milliseconds: 300));
    final landed = tester.getRect(find.byKey(_window));
    expect(landed.left, closeTo(_buttonRect.left, 2));
    expect(landed.top, closeTo(_buttonRect.top, 4));
    expect(landed.width, closeTo(_buttonRect.width, 4));

    await tester.pumpAndSettle();
    expect(find.byKey(_window), findsNothing);
    expect(find.byKey(_button), findsOneWidget);
  });

  testWidgets('кнопки больше нет — экран гаснет на месте', (tester) async {
    await _pumpApp(tester);
    await _tapButton(tester);
    await tester.pumpAndSettle();
    tester.state<_FirstState>(find.byType(_First, skipOffstage: false))
        .hideButton();
    await tester.pump();

    await tester.tap(find.text('назад'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(find.byKey(_window)), Offset.zero & _screen,
        reason: 'складываться некуда: окно не летит в пустое место');
    final fade = tester.widget<Opacity>(find
        .ancestor(of: find.byKey(_window), matching: find.byType(Opacity))
        .first);
    expect(fade.opacity, lessThan(0.8));
    expect(fade.opacity, greaterThan(0));

    await tester.pumpAndSettle();
    expect(find.byKey(_window), findsNothing);
  });

  testWidgets('второй экран от старого нажатия не растёт', (tester) async {
    await _pumpApp(tester);
    await _tapButton(tester);
    await tester.pumpAndSettle();

    // То же касание уже израсходовано: следующий экран открыт программно.
    _navigator.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(_window), findsOneWidget,
        reason: 'окно на экране одно — от первого перехода');
    await tester.pumpAndSettle();
  });

  testWidgets('при «уменьшить движение» работает штатный переход',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpApp(tester);
    await _tapButton(tester);

    expect(find.byKey(_window), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('первый блок'), findsOneWidget);
  });

  testWidgets('выключатель возвращает штатный переход', (tester) async {
    UnfoldPageTransitionsBuilder.enabled = false;
    await _pumpApp(tester);
    await _tapButton(tester);

    expect(find.byKey(_window), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('первый блок'), findsOneWidget);
  });

  testWidgets('экран, заменивший всю стопку, не растёт', (tester) async {
    // Так выходят из аккаунта: кнопка заменяет стопку целиком. Возвращаться
    // некуда, и складываться в исчезнувшую кнопку незачем.
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android:
              UnfoldPageTransitionsBuilder(fallback: _fallback),
        }),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const _Second()),
                (_) => false,
              ),
              child: Container(
                  key: _button, width: 120, height: 48, color: Colors.teal),
            ),
          ),
        ),
      ),
    ));
    await _tapButton(tester);
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byKey(_window), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('первый блок'), findsOneWidget);
  });

  testWidgets('системный жест «назад» Android ведёт тот же экран',
      (tester) async {
    await _pumpApp(tester);
    await _tapButton(tester);
    await tester.pumpAndSettle();

    await _backGesture('startBackGesture', {
      'touchOffset': <double>[5, 400],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await _backGesture('updateBackGestureProgress', {
      'touchOffset': <double>[150, 400],
      'progress': 0.7,
      'swipeEdge': 0,
    });
    await tester.pump();
    expect(tester.getRect(find.byKey(_window)).width,
        lessThan(_screen.width * 0.8));
    expect(find.byKey(_button), findsOneWidget,
        reason: 'под сжатым экраном виден прежний');

    await _backGesture('commitBackGesture');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(_window), findsNothing);
  });

  testWidgets('отменённый системный жест оставляет экран открытым',
      (tester) async {
    await _pumpApp(tester);
    await _tapButton(tester);
    await tester.pumpAndSettle();

    await _backGesture('startBackGesture', {
      'touchOffset': <double>[5, 400],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await _backGesture('updateBackGestureProgress', {
      'touchOffset': <double>[60, 400],
      'progress': 0.3,
      'swipeEdge': 0,
    });
    await tester.pump();
    await _backGesture('cancelBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_window)), Offset.zero & _screen);
    expect(find.text('первый блок'), findsOneWidget);
  });

  group('iPhone', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('жест от левого края сжимает экран и уводит назад',
        (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.byKey(_button));
      await tester.pumpAndSettle();

      final finger = await tester.startGesture(const Offset(4, 400));
      await finger.moveBy(const Offset(30, 0));
      await finger.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(tester.getRect(find.byKey(_window)).width,
          lessThan(_screen.width * 0.9));

      await finger.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_window), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
