import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Экран настроек обновляется после ожидания только пока он открыт.
///
/// Bugsink 23.10.2026, версия 1.38.0: «Null check operator used on a null
/// value» в `_openSettings`. Переключатели (цикл партнёру, значок рядом с
/// кнопкой, экран блокировки) сохраняются с ожиданием, а потом обновляют экран
/// настроек. Закрыл его человек раньше — обновление уходило в снятый экран.
void main() {
  test('настройки обновляются только через обёртку с ctx.mounted', () {
    final src = File('lib/screens/profile_screen.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _openSettings(BuildContext context)');
    expect(start, isNot(-1));
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    final raw = 'setSheetState('.allMatches(body).length;
    expect(raw, 1, reason: 'голый setSheetState только внутри обёртки');
    expect(body, contains('if (ctx.mounted) setSheetState(fn);'));
  });
}
