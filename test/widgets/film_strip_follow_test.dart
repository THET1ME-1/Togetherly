import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/memory_lane_screen.dart';
import 'package:love_app/widgets/memory/media_strip.dart';

/// Обращение 256 (20.10.2026): в полноэкранном просмотре плёнка снизу при
/// листании съезжала влево, пока текущий кадр не уходил за край. Прокрутка
/// считала каждую миниатюру шириной 64 точки, а ширина идёт от пропорции
/// снимка: вертикальный кадр уже, и плёнка проскакивала дальше нужного.
void main() {
  test('середина плёнки считается по настоящим ширинам кадров', () {
    // Отступ 12, кадры 42 и 56 с зазором 2, у выбранного рамка +6.
    final center = filmStripCenter(widths: const [42, 56, 100], index: 2, viewport: 300);
    expect(center, 12 + 44 + 58 + (100 + 6) / 2 - 150);
  });

  List<GalleryItem> portrait(String tag) => [
        for (var i = 0; i < 40; i++)
          GalleryItem(url: 'https://x.test/$tag-$i.jpg', memoryId: 'm$i'),
      ];

  Future<void> open(WidgetTester tester, List<GalleryItem> items, int index) async {
    for (final item in items) {
      MediaAspectCache.put(item.url, 0.75);
    }
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: FullscreenGallery(items: items, initialIndex: index)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Rect selected(WidgetTester tester) =>
      tester.getRect(find.byWidgetPredicate((w) => w is FilmFrame && w.selected));

  testWidgets('открыли на двадцатом кадре — его миниатюра на экране', (tester) async {
    await open(tester, portrait('open'), 20);
    final rect = selected(tester);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(400));
  });

  testWidgets('листаем дальше — текущая миниатюра не уезжает за край', (tester) async {
    await open(tester, portrait('swipe'), 20);
    for (var i = 0; i < 4; i++) {
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }
    final rect = selected(tester);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(400));
  });
}
