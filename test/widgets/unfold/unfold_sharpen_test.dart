import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/unfold/unfold_route.dart';

const _screen = Size(360, 760);
const _near = ValueKey<String>('unfold-flier-chest');
const _far = ValueKey<String>('unfold-flier-chest-far');

/// Мелкая картинка в карточке и та же крупная на экране: так сундук с главной
/// летит на экран сундука. Снимок с карточки втрое мельче места посадки.
class _Home extends StatelessWidget {
  const _Home({required this.small, required this.page});

  final ui.Image small;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: const Alignment(-0.8, 0.6),
        child: UnfoldSource(
          fill: Colors.amber,
          radius: 28,
          builder: (context, source) => GestureDetector(
            key: const ValueKey('card'),
            onTap: () => Navigator.of(context)
                .push(UnfoldRoute<void>(source: source, builder: (_) => page)),
            child: Container(
              width: 280,
              height: 120,
              color: Colors.amber,
              alignment: Alignment.centerLeft,
              child: UnfoldShared(
                tag: 'chest',
                child: RawImage(image: small, width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _page(Widget art) => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: UnfoldShared(tag: 'chest', child: art),
        ),
      ),
    );

Future<({ui.Image small, ui.Image big})> _images(WidgetTester tester) async {
  final small =
      (await tester.runAsync(() => createTestImage(width: 100, height: 100)))!;
  final big =
      (await tester.runAsync(() => createTestImage(width: 300, height: 300)))!;
  addTearDown(small.dispose);
  addTearDown(big.dispose);
  return (small: small, big: big);
}

Future<void> _open(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(_screen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.tap(find.byKey(const ValueKey('card')));
  await tester.pump();
  await tester.pump();
}

double _shown(WidgetTester tester, Key key) => tester
    .widget<Opacity>(
        find.ancestor(of: find.byKey(key), matching: find.byType(Opacity)).first)
    .opacity;

void main() {
  testWidgets('картинка в полёте становится резкой: проступает снимок с '
      'нового экрана', (tester) async {
    final art = await _images(tester);
    await _open(
      tester,
      _Home(
        small: art.small,
        page: _page(RawImage(image: art.big, width: 300, height: 300)),
      ),
    );
    expect(find.byKey(_near), findsOneWidget);
    expect(find.byKey(_far), findsNothing,
        reason: 'со старта летит то, что было в карточке');

    // Новый экран должен хоть раз нарисоваться, прежде чем с него снимут
    // картинку.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(_far), findsOneWidget);
    expect(_shown(tester, _far), greaterThan(0.9),
        reason: 'к середине пути картинка уже в полном разрешении');
    expect(find.byKey(_near), findsOneWidget,
        reason: 'мелкий снимок остаётся под резким: без провала прозрачности');

    await tester.pumpAndSettle();
    expect(find.byKey(_near), findsNothing);
  });

  testWidgets('на новом экране картинка ещё не загрузилась — летит снимок '
      'карточки, пустоты нет', (tester) async {
    final art = await _images(tester);
    await _open(
      tester,
      _Home(
        small: art.small,
        // Картинки ещё нет: место есть, рисовать нечего.
        page: _page(const RawImage(width: 300, height: 300)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(_near), findsOneWidget);
    expect(find.byKey(_far), findsNothing,
        reason: 'снимок пустого места стёр бы картинку посреди полёта');
    await tester.pumpAndSettle();
  });
}
