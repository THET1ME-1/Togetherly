import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Связи экрана холста с кистями и ластиком. Сам экран в тест не встаёт
/// (сервер, канал, очередь), поэтому сторожим места по исходнику: каждая
/// оборванная связь молча превращала бы маркер в перо или стирание в
/// неотменяемое.
void main() {
  final source = File('lib/screens/draw_screen.dart').readAsStringSync();

  String block(String start, [String end = '\n  }\n']) {
    final from = source.indexOf(start);
    expect(from, greaterThanOrEqualTo(0), reason: 'нет «$start»');
    final to = source.indexOf(end, from);
    return source.substring(from, to < 0 ? source.length : to);
  }

  test('кисть едет партнёру в живом мазке и в финальном пакете', () {
    final meta = block('LiveStrokeMeta _liveMeta()', ');');
    expect(meta, contains('brush:'));
    expect(meta, contains('_currentBrush'));
    expect(block('Future<void> _pushLiveDone('), contains('brush: stroke.brush'));
  });

  test('текущая линия и живые мазки партнёра рисуются своей кистью', () {
    final live = block('void _paintLive(');
    expect(live, contains('brush: currentBrush'));
    expect(live, contains('brush: s.brush'));
  });

  test('ластик не сглаживается: стирает точно под пальцем', () {
    expect(block('_stabilizer = StrokeStabilizer(', ')..begin'), contains('DrawTool.eraser'));
  });

  test('кисть, режим и толщина ластика живут на устройстве', () {
    expect(block('Future<void> _loadBrushPrefs()'), contains('smoothingFromPrefs('));
    for (final key in ['kDrawBrush', 'kEraserMode', 'kEraserWidth']) {
      expect(block('Future<void> _loadBrushPrefs()'), contains('UiPrefs.$key'));
      expect(block('Future<void> _saveBrushPrefs()'), contains('UiPrefs.$key'));
    }
  });

  test('отмена знает про стирание линией целиком', () {
    expect(block('Future<void> _undo()'), contains('undoTarget('));
    expect(block('Future<void> _redo()'), contains('undoTarget('));
    expect(block('void _cancelCurrentGesture()'), contains('_endWholeErase()'));
    expect(source, contains('strokesUnderFinger('));
  });

  test('на пиксельном холсте ряда кистей нет', () {
    expect(block('Widget _toolsSheet('), contains('brushes: _isPixel ? null'));
  });
}
