import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_quick_tools.dart';

void main() {
  group('набор быстрых инструментов', () {
    test('по умолчанию шесть кнопок макета плюс ладонь и очистка', () {
      expect(kDefaultQuickTools, [
        DrawQuickTool.brush,
        DrawQuickTool.eraser,
        DrawQuickTool.fill,
        DrawQuickTool.shapes,
        DrawQuickTool.layers,
        DrawQuickTool.image,
        DrawQuickTool.palm,
        DrawQuickTool.clear,
      ]);
    });

    test('пустая настройка даёт набор по умолчанию', () {
      expect(parseQuickTools(null), kDefaultQuickTools);
      expect(parseQuickTools(''), kDefaultQuickTools);
    });

    test('порядок человека сохраняется', () {
      final parsed = parseQuickTools('palm,brush,clear');
      expect(parsed, [
        DrawQuickTool.palm,
        DrawQuickTool.brush,
        DrawQuickTool.clear,
      ]);
    });

    test('незнакомое имя пропускается, а не роняет набор', () {
      // Настройка переживает обновление приложения: инструмент могли убрать.
      expect(parseQuickTools('brush,телепорт,eraser'),
          [DrawQuickTool.brush, DrawQuickTool.eraser]);
    });

    test('повтор в настройке не задваивает кнопку', () {
      expect(parseQuickTools('brush,brush,eraser'),
          [DrawQuickTool.brush, DrawQuickTool.eraser]);
    });

    test('кисть остаётся, даже если её выключили', () {
      // Без кисти холст превращается в просмотрщик: рисовать нечем.
      expect(parseQuickTools('layers,image').first, DrawQuickTool.brush);
    });

    test('больше двенадцати кнопок в панель не помещается', () {
      final many = DrawQuickTool.values.map((t) => t.name).join(',');
      expect(parseQuickTools('$many,$many').length,
          lessThanOrEqualTo(kMaxQuickTools));
    });

    test('набор записывается обратно тем же порядком', () {
      const tools = [DrawQuickTool.palm, DrawQuickTool.brush];
      expect(parseQuickTools(encodeQuickTools(tools)), tools);
    });

    test('строки в панели растут по шесть кнопок', () {
      expect(quickToolRows(6, perRow: 6), 1);
      expect(quickToolRows(7, perRow: 6), 2);
      expect(quickToolRows(12, perRow: 6), 2);
      expect(quickToolRows(4, perRow: 3), 2);
    });
  });
}
