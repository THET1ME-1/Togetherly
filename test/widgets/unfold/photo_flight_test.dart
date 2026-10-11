import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/unfold/photo_flight.dart';
import 'package:love_app/widgets/unfold/unfold_touch.dart';

const _screen = Size(360, 760);
const _flier = ValueKey<String>('photo-flier');
const _thumb = ValueKey<String>('thumb');
const _backdrop = ValueKey<String>('backdrop');
const _photo = ValueKey<String>('photo');
const _thumbRect = Rect.fromLTWH(30, 400, 120, 60);

/// Сцена просмотра: отступ 60 сверху и 140 снизу, кадр 4:3 встаёт по ширине.
const _target = Rect.fromLTWH(0, 205, 360, 270);

final _navigator = GlobalKey<NavigatorState>();

class _Viewer extends StatelessWidget {
  const _Viewer({this.canDismiss = true, this.returns = true});

  final bool canDismiss;
  final bool returns;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(
            child: PhotoFlightBackdrop(
              child: ColoredBox(key: _backdrop, color: Colors.black),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 60, bottom: 140),
            child: PhotoFlightStage(
              canDismiss: canDismiss,
              returns: returns,
              child: SizedBox.expand(
                child: RawImage(
                  key: _photo,
                  image: PhotoFlight.thumbOf(context),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: PhotoFlightChrome(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('закрыть'),
              ),
            ),
          ),
          const Positioned(
            bottom: 8,
            left: 8,
            child: PhotoFlightChrome(index: 1, child: Text('низ')),
          ),
        ],
      ),
    );
  }
}

class _Feed extends StatefulWidget {
  const _Feed({required this.photo, required this.viewer});

  final ui.Image photo;
  final Widget viewer;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  bool thumbShown = true;

  void hideThumb() => setState(() => thumbShown = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (thumbShown)
            Positioned.fromRect(
              rect: _thumbRect,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  PhotoFlightRoute<void>(builder: (_) => widget.viewer),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RawImage(
                      key: _thumb, image: widget.photo, fit: BoxFit.cover),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _pumpFeed(WidgetTester tester,
    {Widget viewer = const _Viewer()}) async {
  await tester.binding.setSurfaceSize(_screen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final photo =
      (await tester.runAsync(() => createTestImage(width: 40, height: 30)))!;
  addTearDown(photo.dispose);
  await tester.pumpWidget(MaterialApp(
    navigatorKey: _navigator,
    home: _Feed(photo: photo, viewer: viewer),
  ));
}

/// Нажатие и первый видимый кадр (самый первый кадр маршрута за сценой).
Future<void> _tapThumb(WidgetTester tester) async {
  await tester.tap(find.byKey(_thumb));
  await tester.pump();
  await tester.pump();
}

double _opacityAbove(WidgetTester tester, Finder of) => tester
    .widget<Opacity>(
        find.ancestor(of: of, matching: find.byType(Opacity)).first)
    .opacity;

void main() {
  setUp(() {
    UnfoldTouch.install();
    UnfoldTouch.forget();
  });

  testWidgets('кадр вылетает из миниатюры и встаёт на своё место',
      (tester) async {
    await _pumpFeed(tester);
    await _tapThumb(tester);

    expect(tester.getRect(find.byKey(_flier)), _thumbRect,
        reason: 'первый кадр обязан совпасть с миниатюрой');
    expect(tester.widget<ClipRRect>(find.byKey(_flier)).borderRadius,
        BorderRadius.circular(12));
    expect(_opacityAbove(tester, find.byKey(_photo)), 0,
        reason: 'пока летит снимок, сам кадр в просмотре не виден');

    await tester.pump(const Duration(milliseconds: 90));
    final flying = tester.getRect(find.byKey(_flier));
    expect(flying.width, greaterThan(_thumbRect.width));
    expect(flying.width, lessThan(_target.width));
    expect(flying.top, lessThan(_thumbRect.top));

    await tester.pump(const Duration(milliseconds: 500));
    final landing = tester.getRect(find.byKey(_flier));
    expect(landing.left, closeTo(_target.left, 1));
    expect(landing.top, closeTo(_target.top, 1));
    expect(landing.width, closeTo(_target.width, 1.5));
    expect(landing.height, closeTo(_target.height, 1.5));

    await tester.pumpAndSettle();
    expect(find.byKey(_flier), findsNothing);
    expect(_opacityAbove(tester, find.byKey(_photo)), 1);
  });

  testWidgets('фон темнеет постепенно, кнопки проявляются следом',
      (tester) async {
    await _pumpFeed(tester);
    await _tapThumb(tester);
    expect(_opacityAbove(tester, find.byKey(_backdrop)), 0);
    expect(find.byKey(_thumb), findsOneWidget,
        reason: 'прежний экран виден под темнеющим фоном');

    await tester.pump(const Duration(milliseconds: 110));
    expect(_opacityAbove(tester, find.byKey(_backdrop)), closeTo(0.5, 0.05));
    expect(_opacityAbove(tester, find.text('закрыть')), 0);

    await tester.pump(const Duration(milliseconds: 120));
    expect(_opacityAbove(tester, find.byKey(_backdrop)), 1);
    expect(_opacityAbove(tester, find.text('закрыть')), greaterThan(0.3));
    expect(_opacityAbove(tester, find.text('низ')), lessThan(0.3));

    await tester.pumpAndSettle();
    expect(_opacityAbove(tester, find.text('низ')), 1);
  });

  testWidgets('«закрыть» отправляет кадр обратно в миниатюру', (tester) async {
    await _pumpFeed(tester);
    await _tapThumb(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('закрыть'));
    await tester.pump();
    expect(tester.getRect(find.byKey(_flier)), _target);

    await tester.pump(const Duration(milliseconds: 100));
    final flying = tester.getRect(find.byKey(_flier));
    expect(flying.width, lessThan(_target.width));
    expect(flying.width, greaterThan(_thumbRect.width));
    expect(_opacityAbove(tester, find.byKey(_backdrop)), lessThan(0.7));

    await tester.pump(const Duration(milliseconds: 300));
    final landed = tester.getRect(find.byKey(_flier));
    expect(landed.left, closeTo(_thumbRect.left, 1.5));
    expect(landed.top, closeTo(_thumbRect.top, 1.5));
    expect(landed.width, closeTo(_thumbRect.width, 2));

    await tester.pumpAndSettle();
    expect(find.byKey(_flier), findsNothing);
    expect(find.byType(_Viewer), findsNothing);
  });

  testWidgets('кадр тянут вниз: едет за пальцем, фон светлеет, отпустили — '
      'закрылся', (tester) async {
    await _pumpFeed(tester);
    await _tapThumb(tester);
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.byKey(_photo));

    final finger = await tester.startGesture(const Offset(180, 340));
    await finger.moveBy(const Offset(0, 30));
    await finger.moveBy(const Offset(0, 150));
    await tester.pump();
    final pulled = tester.getRect(find.byKey(_photo));
    expect(pulled.center.dy, greaterThan(rest.center.dy + 100));
    expect(pulled.width, lessThan(rest.width));
    expect(_opacityAbove(tester, find.byKey(_backdrop)), lessThan(0.7));
    expect(_opacityAbove(tester, find.text('закрыть')), 0);

    await finger.up();
    await tester.pump();
    expect(find.byKey(_flier), findsOneWidget,
        reason: 'отпущенный кадр летит в миниатюру оттуда, где его держали');
    expect(tester.getRect(find.byKey(_flier)).center.dy,
        greaterThan(_target.center.dy + 100));
    await tester.pumpAndSettle();
    expect(find.byType(_Viewer), findsNothing);
  });

  testWidgets('короткий жест возвращает кадр на место', (tester) async {
    await _pumpFeed(tester);
    await _tapThumb(tester);
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.byKey(_photo));

    final finger = await tester.startGesture(const Offset(180, 340));
    await finger.moveBy(const Offset(0, 30));
    await finger.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(tester.getRect(find.byKey(_photo)).top, greaterThan(rest.top));
    await finger.up();
    await tester.pumpAndSettle();

    expect(find.byType(_Viewer), findsOneWidget);
    expect(tester.getRect(find.byKey(_photo)), rest);
    expect(_opacityAbove(tester, find.byKey(_backdrop)), 1);
    expect(_opacityAbove(tester, find.text('закрыть')), 1);
  });

  testWidgets('увеличенный кадр жест «вниз» не закрывает', (tester) async {
    await _pumpFeed(tester, viewer: const _Viewer(canDismiss: false));
    await _tapThumb(tester);
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.byKey(_photo));

    await tester.drag(find.byKey(_photo), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.byType(_Viewer), findsOneWidget);
    expect(tester.getRect(find.byKey(_photo)), rest);
  });

  testWidgets('пролистали к другому кадру — просмотр гаснет без полёта',
      (tester) async {
    await _pumpFeed(tester, viewer: const _Viewer(returns: false));
    await _tapThumb(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('закрыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_flier), findsNothing);
    expect(_opacityAbove(tester, find.byKey(_photo)), lessThan(1));
    await tester.pumpAndSettle();
    expect(find.byType(_Viewer), findsNothing);
  });

  testWidgets('миниатюры больше нет — просмотр гаснет без полёта',
      (tester) async {
    await _pumpFeed(tester);
    await _tapThumb(tester);
    await tester.pumpAndSettle();
    tester.state<_FeedState>(find.byType(_Feed)).hideThumb();
    await tester.pump();

    await tester.tap(find.text('закрыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_flier), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(_Viewer), findsNothing);
  });

  testWidgets('открыли не касанием — просмотр проявляется на месте',
      (tester) async {
    await _pumpFeed(tester);
    _navigator.currentState!
        .push(PhotoFlightRoute<void>(builder: (_) => const _Viewer()));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    expect(find.byKey(_flier), findsNothing);
    expect(_opacityAbove(tester, find.byKey(_backdrop)), closeTo(0.5, 0.05));
    expect(_opacityAbove(tester, find.byKey(_photo)), closeTo(0.5, 0.05));
    await tester.pumpAndSettle();
    expect(_opacityAbove(tester, find.byKey(_photo)), 1);
  });

  testWidgets('закрыли посреди полёта — кадр возвращается с полпути',
      (tester) async {
    await _pumpFeed(tester);
    await _tapThumb(tester);
    await tester.pump(const Duration(milliseconds: 90));
    final midway = tester.getRect(find.byKey(_flier));

    _navigator.currentState!.pop();
    await tester.pump();
    expect(tester.getRect(find.byKey(_flier)).width,
        closeTo(midway.width, 1));
    await tester.pumpAndSettle();
    expect(find.byType(_Viewer), findsNothing);
  });

  testWidgets('при «уменьшить движение» кадр не летит', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpFeed(tester);
    await _tapThumb(tester);
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(_flier), findsNothing);
    await tester.pumpAndSettle();
    expect(_opacityAbove(tester, find.byKey(_photo)), 1);

    await tester.drag(find.byKey(_photo), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.byType(_Viewer), findsOneWidget,
        reason: 'жест — тоже движение: с ним просмотр закрывают кнопкой');
  });

  testWidgets('вне маршрута обёртки ничего не делают', (tester) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: _Viewer()));

    expect(find.ancestor(of: find.byKey(_backdrop), matching: find.byType(Opacity)),
        findsNothing);
    expect(find.text('закрыть'), findsOneWidget);
    await tester.drag(find.byKey(_photo), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.byType(_Viewer), findsOneWidget);
  });
}
