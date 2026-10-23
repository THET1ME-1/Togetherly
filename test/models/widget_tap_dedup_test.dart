import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_tap_dedup.dart';

/// TOG-13: после входа в заметку с виджета «назад» приходилось жать несколько
/// раз. Одно нажатие на виджет доходит до главной разными путями: стартовая
/// ссылка home_widget, его поток, поток DeepLinkService (туда пишут системный
/// канал маршрутов, стартовая ссылка app_links и его поток) и буфер холодного
/// старта. Каждый приход открывал лист заметки ещё раз.
void main() {
  final t0 = DateTime(2026, 10, 23, 15);
  final note = Uri.parse('loveapp://note');

  test('то же нажатие, пришедшее вторым путём, не открывает лист снова', () {
    final taps = WidgetTapDedup();
    expect(taps.admit(note, t0), isTrue);
    expect(taps.admit(note, t0.add(const Duration(milliseconds: 800))), isFalse);
  });

  test('другое действие проходит сразу', () {
    final taps = WidgetTapDedup();
    expect(taps.admit(note, t0), isTrue);
    expect(taps.admit(Uri.parse('loveapp://mood?id=happy'),
        t0.add(const Duration(milliseconds: 300))), isTrue);
  });

  test('новое нажатие через несколько секунд проходит', () {
    final taps = WidgetTapDedup();
    expect(taps.admit(note, t0), isTrue);
    expect(taps.admit(note, t0.add(const Duration(seconds: 4))), isTrue);
  });

  test('главная пропускает каждое нажатие через фильтр и чистит буфер', () {
    final src = File('lib/screens/home_screen.dart').readAsStringSync();
    final start = src.indexOf('void _handleWidgetUri(Uri uri) {');
    final head = src.substring(start, start + 300);
    expect(head, contains('_widgetTaps.admit(uri'));
    // Ссылка, пришедшая потоком, лежит и в буфере холодного старта: без
    // очистки новая главная откроет её ещё раз.
    final listen = src.indexOf('widgetActionStream.listen(');
    expect(src.substring(listen, listen + 400),
        contains('consumePendingWidgetAction()'));
  });
}
