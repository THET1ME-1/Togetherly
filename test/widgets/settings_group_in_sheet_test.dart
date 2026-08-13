import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/animations.dart';
import 'package:love_app/widgets/settings_scaffold.dart';

/// Строки настроек в нижнем листе должны быть ВИДНЫ, а не только нажимаемы.
///
/// `SettingsGroup` заворачивает каждую строку в появление по прокрутке, а лист
/// на первом кадре ещё едет снизу: строки считались «не доехавшими» и
/// оставались прозрачными. Нажатия при этом проходили — `Opacity(0)` их не
/// блокирует, — поэтому жалоба звучала как «на всех попапах не отображается
/// текст, хотя он есть и кликабельный» (скриншоты «Пол» и «Выберите язык»,
/// 13 августа 2026).
///
/// Так собраны все листы приложения: пол, язык, уведомления, оформление.
void main() {
  testWidgets('строки листа видны после его появления', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => SettingsGroup([
                    SettingsRow(
                      icon: Icons.male_rounded,
                      title: 'Мужской',
                      onTap: () {},
                    ),
                    SettingsRow(
                      icon: Icons.female_rounded,
                      title: 'Женский',
                      onTap: () {},
                    ),
                  ]),
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    for (final label in ['Мужской', 'Женский']) {
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text(label), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 1.0, reason: 'строка «$label» осталась невидимой');
    }
  });

  testWidgets('без прокрутки и без маршрута блок всё равно виден',
      (tester) async {
    // Страховка на будущее: любой контейнер, у которого нет ни прокрутки, ни
    // анимации появления (например, всплывашка через Overlay), не должен
    // оставлять содержимое прозрачным.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppearOnScroll(child: Text('Видно сразу')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Видно сразу'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1.0);
  });
}
