import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/settings_scaffold.dart';

/// Настройки со значками у заголовков секций — было и стало, на живой теме.
///
/// Имя без `_test`: файл для глаз, обычный `flutter test` его не подхватывает.
/// Запуск: `flutter test test/goldens/settings_sections_preview.dart`,
/// картинка в `build/qr-preview/settings-sections.png`.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    any = true;
  }
  if (any) await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('заголовки секций настроек', (tester) async {
    tester.view.physicalSize = const Size(920, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    // Розовая палитра — та же, что на снимке от заказчика.
    final t = buildAppTheme(kPalettes[1], Brightness.light);
    final cs = t.scheme!;

    Widget row(IconData icon, String title, String subtitle) => SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: const SettingsChevron(),
      onTap: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: cs.surface,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListView(
                  children: [
                    const SettingsSection(
                      'Оформление',
                      icon: Icons.brush_rounded,
                    ),
                    SettingsGroup([
                      row(
                        Icons.palette_rounded,
                        'Оформление',
                        'Тема, палитра, насыщенность',
                      ),
                      row(Icons.apps_rounded, 'Иконка приложения', 'Розовая'),
                      row(Icons.translate_rounded, 'Язык', 'Русский'),
                    ]),
                    const SettingsSection(
                      'Уведомления',
                      icon: Icons.campaign_rounded,
                    ),
                    SettingsGroup([
                      row(
                        Icons.notifications_rounded,
                        'Уведомления',
                        'Что и когда присылать',
                      ),
                      row(
                        Icons.lock_clock_rounded,
                        'Показывать на экране блокировки',
                        'Настроение партнёра на экране блокировки',
                      ),
                    ]),
                    const SettingsSection(
                      'Цикл',
                      icon: Icons.water_drop_rounded,
                    ),
                    SettingsGroup([
                      row(
                        Icons.visibility_rounded,
                        'Показывать партнёру',
                        'Отметки цикла видит вторая половина',
                      ),
                    ]),
                    SettingsSection(
                      'Аккаунт',
                      icon: Icons.person_rounded,
                      color: cs.error,
                    ),
                    SettingsGroup([
                      row(Icons.logout_rounded, 'Выйти', 'До встречи'),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File(
        '${dir.path}/settings-sections.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
