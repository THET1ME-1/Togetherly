import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';

const _screen = Size(360, 760);
const _window = ValueKey<String>('unfold-window');

/// Экран, который открывается: обложка сверху и пара блоков под ней.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: UnfoldShared(
              tag: 'cover',
              radius: 22,
              child: SizedBox(
                key: ValueKey('page-cover'),
                width: 336,
                height: 200,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
          // То же имя, но крупнее и жирнее: в полёте одно начертание обязано
          // перетечь в другое, а не подмениться в момент посадки.
          const UnfoldShared(
            tag: 'name',
            fit: UnfoldFit.scale,
            child: Text('Аня',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ),
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

/// Лента с одной карточкой: карточка стоит не в углу, чтобы рост окна было
/// видно по всем четырём сторонам.
class _Feed extends StatelessWidget {
  const _Feed({this.withSource = true});

  final bool withSource;

  void _open(BuildContext context, UnfoldSourceState? source) {
    Navigator.of(context).push(
      UnfoldRoute<void>(source: source, builder: (_) => const _Page()),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget card(VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            key: const ValueKey('card'),
            width: 300,
            height: 180,
            color: Colors.pink,
            alignment: Alignment.topLeft,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UnfoldShared(
                  tag: 'cover',
                  radius: 22,
                  child: SizedBox(
                    key: ValueKey('card-cover'),
                    width: 150,
                    height: 90,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
                UnfoldShared(
                  tag: 'name',
                  fit: UnfoldFit.scale,
                  child: Text('Аня', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        );
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(left: 30, top: 300),
        child: Align(
          alignment: Alignment.topLeft,
          child: withSource
              ? UnfoldSource(
                  fill: Colors.pink,
                  radius: 28,
                  builder: (context, source) =>
                      card(() => _open(context, source)),
                )
              : Builder(builder: (context) => card(() => _open(context, null))),
        ),
      ),
    );
  }
}

Future<void> _pumpFeed(WidgetTester tester, {bool withSource = true}) async {
  await tester.binding.setSurfaceSize(_screen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: _Feed(withSource: withSource)));
}

/// Нажатие и первый видимый кадр. Самый первый кадр нового маршрута Flutter
/// держит за сценой (меряет героев), на экране он не появляется.
Future<void> _tapCard(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('card')));
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
  const cardRect = Rect.fromLTWH(30, 300, 300, 180);

  testWidgets('экран вырастает из карточки до полного', (tester) async {
    await _pumpFeed(tester);
    expect(tester.getRect(find.byKey(const ValueKey('card'))), cardRect);

    await _tapCard(tester);
    expect(tester.getRect(find.byKey(_window)), cardRect,
        reason: 'первый кадр обязан совпасть с карточкой, иначе виден скачок');

    await tester.pump(const Duration(milliseconds: 60));
    final growing = tester.getRect(find.byKey(_window));
    expect(growing.width, greaterThan(cardRect.width));
    expect(growing.width, lessThan(_screen.width));
    expect(growing.top, lessThan(cardRect.top));

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_window)), Offset.zero & _screen);
    expect(find.text('первый блок'), findsOneWidget);
  });

  testWidgets('карточка спрятана, пока экран открыт, и возвращается после',
      (tester) async {
    await _pumpFeed(tester);
    final source = tester.state<UnfoldSourceState>(find.byType(UnfoldSource));
    expect(source.hidden, isFalse);

    await _tapCard(tester);
    expect(source.hidden, isTrue);
    await tester.pumpAndSettle();
    expect(source.hidden, isTrue);

    await tester.tap(find.text('назад'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final folding = tester.getRect(find.byKey(_window));
    expect(folding.width, lessThan(_screen.width));
    expect(folding.width, greaterThan(cardRect.width));

    await tester.pumpAndSettle();
    expect(find.byKey(_window), findsNothing);
    expect(source.hidden, isFalse);
  });

  testWidgets('карточка появляется в том же кадре, где исчезло окно',
      (tester) async {
    await _pumpFeed(tester);
    final source = tester.state<UnfoldSourceState>(find.byType(UnfoldSource));
    await _tapCard(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('назад'));

    var frames = 0;
    do {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    } while (find.byKey(_window).evaluate().isNotEmpty && frames < 80);

    expect(frames, lessThan(80), reason: 'экран так и не закрылся');
    expect(source.hidden, isFalse);
    // Смотрим на то, что нарисовано в этом кадре, а не на флаг: флаг мог
    // смениться после сборки, и карточка появилась бы кадром позже.
    final veil = tester.widget<ClipRect>(find
        .descendant(
            of: find.byType(UnfoldSource), matching: find.byType(ClipRect))
        .first);
    expect(veil.clipper, isNull,
        reason: 'кадр без окна и без карточки — это мигание на месте записи');
  });

  testWidgets('обложка летит от карточки на своё место в экране',
      (tester) async {
    await _pumpFeed(tester);
    const flier = ValueKey<String>('unfold-flier-cover');
    final from = tester.getRect(find.byKey(const ValueKey('card-cover')));

    await _tapCard(tester);
    expect(tester.getRect(find.byKey(flier)), from);

    await tester.pump(const Duration(milliseconds: 66));
    final flying = tester.getRect(find.byKey(flier));
    expect(flying.top, lessThan(from.top), reason: 'обложке вверх, к шапке');
    expect(flying.width, greaterThan(from.width));
    expect(flying.width, lessThan(336));

    await tester.pumpAndSettle();
    expect(find.byKey(flier), findsNothing,
        reason: 'после посадки на экране остаётся настоящая обложка');
    expect(tester.getRect(find.byKey(const ValueKey('page-cover'))),
        const Rect.fromLTWH(12, 60, 336, 200));
    final landed = tester.state<UnfoldSharedState>(find.ancestor(
        of: find.byKey(const ValueKey('page-cover')),
        matching: find.byType(UnfoldShared)));
    expect(landed.hidden, isFalse);
  });

  testWidgets('текст в полёте перетекает из старого начертания в новое',
      (tester) async {
    await _pumpFeed(tester);
    const near = ValueKey<String>('unfold-flier-name-near');
    const far = ValueKey<String>('unfold-flier-name-far');
    double shown(Key key) => tester
        .widget<Opacity>(
            find.ancestor(of: find.byKey(key), matching: find.byType(Opacity))
                .first)
        .opacity;

    await _tapCard(tester);
    expect(find.byKey(near), findsOneWidget);
    expect(shown(near), 1, reason: 'со старта летит то, что было в карточке');

    // Новое начертание снимается с уже нарисованного экрана — на это уходит
    // пара кадров.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(far), findsOneWidget);
    expect(shown(far), greaterThan(0.9),
        reason: 'к середине пути буквы уже новые');
    expect(shown(near), lessThan(0.1));

    await tester.pumpAndSettle();
    expect(find.byKey(far), findsNothing);
  });

  testWidgets('в полёте настоящая обложка экрана спрятана', (tester) async {
    await _pumpFeed(tester);
    await _tapCard(tester);
    await tester.pump(const Duration(milliseconds: 80));
    final target = tester.state<UnfoldSharedState>(find.ancestor(
        of: find.byKey(const ValueKey('page-cover')),
        matching: find.byType(UnfoldShared)));
    expect(target.hidden, isTrue,
        reason: 'иначе обложек на экране две: летящая и стоящая');
  });

  testWidgets('блоки экрана проявляются по очереди', (tester) async {
    await _pumpFeed(tester);
    await _tapCard(tester);
    expect(_opacityOf(tester, 'первый блок'), 0);

    await tester.pump(const Duration(milliseconds: 200));
    final first = _opacityOf(tester, 'первый блок');
    final sixth = _opacityOf(tester, 'шестой блок');
    expect(first, greaterThan(0.5));
    expect(sixth, lessThan(first));

    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'первый блок'), 1);
    expect(_opacityOf(tester, 'шестой блок'), 1);
  });

  testWidgets('без карточки экран проявляется на месте', (tester) async {
    await _pumpFeed(tester, withSource: false);
    await _tapCard(tester);
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getRect(find.byKey(_window)), Offset.zero & _screen,
        reason: 'расти не из чего — окно сразу во весь экран');
    await tester.pumpAndSettle();
    expect(find.text('первый блок'), findsOneWidget);

    await tester.tap(find.text('назад'));
    await tester.pumpAndSettle();
    expect(find.byKey(_window), findsNothing);
  });

  testWidgets('при «уменьшить движение» окно не растёт', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpFeed(tester);
    final source = tester.state<UnfoldSourceState>(find.byType(UnfoldSource));
    await _tapCard(tester);
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getRect(find.byKey(_window)), Offset.zero & _screen);
    await tester.pumpAndSettle();
    expect(source.hidden, isFalse);
  });

  group('жест от края на iPhone', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('экран сжимается и едет за пальцем', (tester) async {
      await _pumpFeed(tester);
      await tester.tap(find.byKey(const ValueKey('card')));
      await tester.pumpAndSettle();

      final finger = await tester.startGesture(const Offset(4, 400));
      await finger.moveBy(const Offset(30, 0));
      await finger.moveBy(const Offset(120, 0));
      await tester.pump();
      final held = tester.getRect(find.byKey(_window));
      expect(held.width, lessThan(_screen.width * 0.9));
      expect(held.left, greaterThan(40));
      expect(find.byKey(const ValueKey('card')), findsOneWidget,
          reason: 'под сжатым экраном должна быть видна лента');

      await finger.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_window), findsNothing, reason: 'за порогом — назад');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('жест работает и там, где экран открылся без карточки',
        (tester) async {
      await _pumpFeed(tester, withSource: false);
      await tester.tap(find.byKey(const ValueKey('card')));
      await tester.pumpAndSettle();

      final finger = await tester.startGesture(const Offset(4, 400));
      await finger.moveBy(const Offset(30, 0));
      await finger.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(tester.getRect(find.byKey(_window)).width,
          lessThan(_screen.width * 0.9),
          reason: 'на iPhone другого способа уйти назад жестом нет');
      await finger.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_window), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('короткий жест возвращает экран на место', (tester) async {
      await _pumpFeed(tester);
      await tester.tap(find.byKey(const ValueKey('card')));
      await tester.pumpAndSettle();

      final finger = await tester.startGesture(const Offset(4, 400));
      await finger.moveBy(const Offset(25, 0));
      await finger.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(tester.getRect(find.byKey(_window)).width,
          lessThan(_screen.width));
      await finger.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_window)), Offset.zero & _screen);
      expect(find.text('первый блок'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('штатный Hero летит на своё настоящее место, а не в окно',
      (tester) async {
    // Круглая кнопка нижней панели — Hero, общий для главной и ленты. Его
    // цель Flutter меряет в первом, невидимом кадре маршрута: если окно в
    // этот момент сжато до плитки, кнопка летит в сжатое место и в конце
    // прыгает.
    const target = Rect.fromLTWH(300, 700, 40, 40);
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget dot(Color color) => Hero(
          tag: 'side',
          child: ColoredBox(key: const ValueKey('dot'), color: color),
        );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(left: 20, top: 20, width: 20, height: 20, child: dot(Colors.red)),
            Positioned(
              left: 60,
              top: 300,
              child: UnfoldSource(
                fill: Colors.pink,
                builder: (context, source) => GestureDetector(
                  onTap: () => Navigator.of(context).push(UnfoldRoute<void>(
                    source: source,
                    builder: (_) => Scaffold(
                      body: Stack(children: [
                        Positioned.fromRect(rect: target, child: dot(Colors.red)),
                      ]),
                    ),
                  )),
                  child: Container(
                      key: const ValueKey('card'),
                      width: 200,
                      height: 100,
                      color: Colors.pink),
                ),
              ),
            ),
          ],
        ),
      ),
    ));

    await _tapCard(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final flying = tester.getRect(find.byKey(const ValueKey('dot')).last);
    expect(flying.left, closeTo(target.left, 4));
    expect(flying.top, closeTo(target.top, 4));
    expect(flying.width, closeTo(target.width, 3));
    await tester.pumpAndSettle();
  });

  testWidgets('без плитки экран открывается обычным маршрутом Material',
      (tester) async {
    await _pumpFeed(tester);
    final source = tester.state<UnfoldSourceState>(find.byType(UnfoldSource));
    Widget page(BuildContext _) => const _Page();

    expect(unfoldFrom<void>(source, page), isA<UnfoldRoute<void>>());
    // Уведомление, кнопка без своей плитки: расти не из чего, и прежний
    // системный переход с жестом «назад» терять нельзя.
    expect(unfoldFrom<void>(null, page), isA<MaterialPageRoute<void>>());
    const settings = RouteSettings(name: '/chat');
    expect(unfoldFrom<void>(null, page, settings: settings).settings.name,
        '/chat');
    expect(unfoldFrom<void>(source, page, settings: settings).settings.name,
        '/chat');
  });

  testWidgets('системный жест «назад» Android ведёт тот же экран',
      (tester) async {
    await _pumpFeed(tester);
    await tester.tap(find.byKey(const ValueKey('card')));
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
    final held = tester.getRect(find.byKey(_window));
    expect(held.width, lessThan(_screen.width * 0.8));

    await _backGesture('commitBackGesture');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(_window), findsNothing);
    final source = tester.state<UnfoldSourceState>(find.byType(UnfoldSource));
    expect(source.hidden, isFalse);
  });

  testWidgets('отменённый системный жест оставляет экран открытым',
      (tester) async {
    await _pumpFeed(tester);
    await tester.tap(find.byKey(const ValueKey('card')));
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
  });
}
