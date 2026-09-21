import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/canvas/canvas_widget_keys.dart';

void main() {
  const items = [
    CanvasWidgetItem(
      id: 'canvas_1785057256005',
      name: 'Наш вечер',
      path: '/data/canvas_widget/c1.png',
      updatedMs: 1785057256005,
    ),
    CanvasWidgetItem(
      id: 'main',
      name: 'Холст',
      path: '/data/canvas_widget/main.png',
      updatedMs: 1784978089414,
    ),
  ];

  test('каждый холст уезжает своим ключом', () {
    final keys = canvasWidgetKeys(
      groupId: 'grp1',
      items: items,
      activeId: 'canvas_1785057256005',
    );

    expect(keys['canvas_grp1_canvas_1785057256005_path'], '/data/canvas_widget/c1.png');
    expect(keys['canvas_grp1_canvas_1785057256005_name'], 'Наш вечер');
    expect(keys['canvas_grp1_main_path'], '/data/canvas_widget/main.png');
    expect(keys['canvas_grp1_active'], 'canvas_1785057256005');
    expect(keys['canvas_grp1_count'], '2');
    expect(keys['canvas_latest_group'], 'grp1');
  });

  test('список для экрана выбора хранит порядок', () {
    final keys = canvasWidgetKeys(groupId: 'g', items: items, activeId: 'main');
    expect(keys['canvas_g_list'], 'canvas_1785057256005,main');
  });

  test('без группы ключи уходят под solo', () {
    final keys = canvasWidgetKeys(groupId: '', items: items, activeId: 'main');
    expect(keys['canvas_solo_active'], 'main');
    expect(keys['canvas_latest_group'], 'solo');
  });

  test('пустой список не ломает ключи', () {
    final keys = canvasWidgetKeys(groupId: 'g', items: const [], activeId: '');
    expect(keys['canvas_g_count'], '0');
    expect(keys['canvas_g_list'], '');
    expect(keys['canvas_g_active'], '');
  });

  test('провайдеры перечислены все три', () {
    expect(kCanvasWidgetProviders.length, 3);
    expect(
      kCanvasWidgetProviders,
      containsAll(const [
        'CanvasWidget2x2Provider',
        'CanvasWidget2x3Provider',
        'CanvasWidget4x4Provider',
      ]),
    );
  });
}
