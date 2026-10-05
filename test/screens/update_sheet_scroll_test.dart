import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Лист обновления без isScrollControlled Flutter режет по 9/16 высоты
/// экрана, и с длинными заметками кнопка «Обновить» уезжала под системную
/// панель (обращение 236, 05.10.2026).
void main() {
  test('оба листа обновления раскрываются на всю высоту', () {
    final src = File('lib/screens/home_screen.dart').readAsStringSync();
    for (final name in ['_showGithubUpdateSheet', '_showUpdateSheet']) {
      final m = RegExp('void $name\\([^)]*\\) \\{([\\s\\S]*?)builder:').firstMatch(src);
      expect(m, isNotNull, reason: name);
      expect(m!.group(1), contains('isScrollControlled: true'), reason: name);
      expect(m.group(1), contains('useSafeArea: true'), reason: name);
    }
  });
}
