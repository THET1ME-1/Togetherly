import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/user_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Обращение 464 (24.10.2026): «Посмотреть» у платной темы красило ею всё
/// приложение, пока его не перезапустят, и платная тема выходила бесплатной.
/// Просмотр живёт [UserData.themePreviewDuration] и гаснет сам.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paid = 13;
  const other = 16;
  const tick = Duration(seconds: 1);

  test('Просмотр платной темы гаснет сам', () {
    fakeAsync((async) {
      final data = UserData();
      final own = data.theme.index;
      var notified = 0;
      data.addListener(() => notified++);

      data.setPreviewTheme(paid);
      expect(data.theme.index, paid);

      async.elapse(UserData.themePreviewDuration - tick);
      expect(data.isPreviewingTheme, isTrue);

      async.elapse(tick);
      expect(data.isPreviewingTheme, isFalse);
      expect(data.previewThemeId, isNull);
      expect(data.theme.index, own);
      expect(notified, 2, reason: 'экраны перерисовываются в своей теме');
    });
  });

  test('Новый просмотр начинает срок заново', () {
    fakeAsync((async) {
      final data = UserData();
      data.setPreviewTheme(paid);
      async.elapse(UserData.themePreviewDuration ~/ 2);
      data.setPreviewTheme(other);

      async.elapse(UserData.themePreviewDuration - tick);
      expect(data.previewThemeId, other);

      async.elapse(tick);
      expect(data.previewThemeId, isNull);
    });
  });

  test('Закрытый просмотр не обрывает следующий раньше срока', () {
    fakeAsync((async) {
      final data = UserData();
      data.setPreviewTheme(paid);
      async.elapse(UserData.themePreviewDuration ~/ 2);
      data.setPreviewTheme(null);
      data.setPreviewTheme(other);

      async.elapse(UserData.themePreviewDuration - tick);
      expect(data.previewThemeId, other);
    });
  });

  // Там же, 07:22: «после первого бага я не могу поменять фон обратно».
  // Выбор сохранялся, а экран так и оставался в просматриваемой теме.
  test('Выбор своей темы снимает просмотр', () {
    SharedPreferences.setMockInitialValues({});
    fakeAsync((async) {
      final data = UserData();
      data.setPreviewTheme(paid);

      data.setThemeId(3);
      async.flushMicrotasks();

      expect(data.isPreviewingTheme, isFalse);
      expect(data.previewEndsAt, isNull);
      expect(data.theme.index, 3);
    });
  });

  test('Своя новая тема тоже снимает просмотр', () {
    SharedPreferences.setMockInitialValues({});
    fakeAsync((async) {
      final data = UserData();
      data.setPreviewTheme(paid);

      data.addCustomThemeColor(const Color(0xFF2E7D32));
      async.flushMicrotasks();

      expect(data.isPreviewingTheme, isFalse);
      expect(data.theme.index, data.themeId);
    });
  });

  test('Конец просмотра известен экрану', () {
    fakeAsync((async) {
      final data = UserData();
      expect(data.previewEndsAt, isNull);

      final before = DateTime.now();
      data.setPreviewTheme(paid);
      final gap = data.previewEndsAt!.difference(before);
      expect(gap, greaterThanOrEqualTo(UserData.themePreviewDuration));
      expect(gap, lessThan(UserData.themePreviewDuration + tick * 2));

      data.setPreviewTheme(null);
      expect(data.previewEndsAt, isNull);
    });
  });
}
