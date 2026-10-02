import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/home_layout.dart';

/// Перетаскивание блоков главной: та же связка, что в `_buildHomeBlocks`
/// (`CustomScrollView` + `SliverReorderableList` + долгое нажатие), и тот же
/// перевод индексов `onReorder` в раскладку через [HomeLayout.dragged].
/// Карта спрятана — её место среди соседей не должно поехать.
void main() {
  testWidgets('зажал блок, протащил вниз — порядок сохранился', (tester) async {
    var layout = const HomeLayout().withBlock(HomeBlock.map, shown: false);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            final shown = layout.visibleBlocks;
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 50)),
                SliverReorderableList(
                  itemCount: shown.length,
                  onReorder: (from, to) => setState(
                      () => layout = layout.dragged(shown, from, to)),
                  proxyDecorator: (child, _, _) =>
                      Material(color: Colors.transparent, child: child),
                  itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                    key: ValueKey(shown[i]),
                    index: i,
                    child: SizedBox(height: 80, child: Text(shown[i].name)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ));

    // Сундук (верхний) зажимаем и тащим ниже заданий.
    final start = tester.getCenter(find.text('chest'));
    final g = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    // Сундук уехал вниз, и экран после броска совпадает с сохранённым
    // порядком: перевод индексов onReorder ничего не перепутал.
    expect(layout.visibleBlocks.first, isNot(HomeBlock.chest));
    final onScreen = [...layout.visibleBlocks]..sort((a, b) => tester
        .getTopLeft(find.text(a.name))
        .dy
        .compareTo(tester.getTopLeft(find.text(b.name)).dy));
    expect(onScreen, layout.visibleBlocks);
    expect(layout.hiddenBlocks, {HomeBlock.map});
    // Спрятанная карта осталась перед заданиями, как и стояла.
    expect(layout.order.indexOf(HomeBlock.map),
        layout.order.indexOf(HomeBlock.tasks) - 1);
  });
}
