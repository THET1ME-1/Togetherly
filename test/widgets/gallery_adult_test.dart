import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/memory_lane_screen.dart';
import 'package:love_app/widgets/memory/adult_veil.dart';

/// Обращение 256 (11.10.2026): полноэкранный просмотр листает кадры сквозь
/// все записи, и свайп из соседней записи приводил на снимок 18+ открытым.
void main() {
  const plain = GalleryItem(url: 'https://x.test/a.jpg', memoryId: 'plain');
  const adult1 =
      GalleryItem(url: 'https://x.test/b.jpg', memoryId: 'hot', adult: true);
  const adult2 =
      GalleryItem(url: 'https://x.test/c.jpg', memoryId: 'hot', adult: true);

  Future<void> open(WidgetTester tester, int index) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: FullscreenGallery(
        items: const [plain, adult1, adult2],
        initialIndex: index,
      ),
    ));
    await tester.pump();
  }

  // Завеса на самом кадре крупнее, чем на плитках плёнки.
  Finder pageVeil() => find.byWidgetPredicate(
      (w) => w is AdultVeil && w.iconSize > 20);
  Finder stripVeil() => find.byWidgetPredicate(
      (w) => w is AdultVeil && w.iconSize <= 20);

  testWidgets('свайп на снимок 18+ показывает его под завесой', (tester) async {
    await open(tester, 0);
    expect(pageVeil(), findsNothing);
    expect(stripVeil(), findsNWidgets(2));

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(pageVeil(), findsOneWidget);
  });

  testWidgets('касание раскрывает все кадры этой записи', (tester) async {
    await open(tester, 0);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    // Раскрытый кадр крутит индикатор загрузки (сети в тесте нет), поэтому
    // дальше кадры считаем сами, а не ждём покоя.
    await tester.tap(pageVeil());
    await tester.pump();
    expect(pageVeil(), findsNothing);
    expect(stripVeil(), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(pageVeil(), findsNothing);
  });

  testWidgets('кадр, открытый касанием по закрытой миниатюре, уже раскрыт',
      (tester) async {
    await open(tester, 1);
    expect(pageVeil(), findsNothing);
    expect(stripVeil(), findsNothing);
  });
}
