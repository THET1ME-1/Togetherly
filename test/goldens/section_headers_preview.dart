import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/settings_scaffold.dart';

/// Заголовки секций и залитая кнопка — было и стало, на настоящей теме.
///
/// Имя без `_test`: файл для глаз. Запуск:
/// `flutter test test/goldens/section_headers_preview.dart`, картинка в
/// `build/qr-preview/`.
void main() {
  testWidgets('заголовки и кнопка', (tester) async {
    tester.view.physicalSize = const Size(1100, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final t = buildAppTheme(kPalettes[7], Brightness.light);
    final cs = t.scheme!;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: cs.surface,
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('БЫЛО — шесть стилей'),
                  const SizedBox(height: 10),
                  _Old('Друзья', 'Unbounded', 16, 0.2, cs.primary),
                  _Old('Настройки', 'Unbounded', 18, -0.3, cs.primary),
                  _Old('ДОСТИЖЕНИЯ', 'Onest', 12, 0.6, cs.onSurfaceVariant),
                  _Old('Задания', 'Onest', 13, 0, cs.onSurfaceVariant),
                  const SizedBox(height: 26),
                  const Text('СТАЛО — один'),
                  const SizedBox(height: 10),
                  _New('Друзья', cs, icon: Icons.group_rounded),
                  _New('Статистика отношений', cs,
                      icon: Icons.insights_rounded),
                  const SettingsSection('Уведомления'),
                  _New('Достижения', cs),
                  const SizedBox(height: 30),
                  const Text('Кнопка каталога виджетов'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                    label: const Text('Добавить на рабочий стол'),
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: const Text('Открыть с Togetherly+'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.secondaryContainer,
                      foregroundColor: cs.onSecondaryContainer,
                    ),
                  ),
                ],
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
      File('${dir.path}/section-headers.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}

class _Old extends StatelessWidget {
  const _Old(this.text, this.font, this.size, this.spacing, this.color);

  final String text;
  final String font;
  final double size;
  final double spacing;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: font,
            fontSize: size,
            fontWeight: FontWeight.w700,
            letterSpacing: spacing,
            color: color,
          ),
        ),
      );
}

class _New extends StatelessWidget {
  const _New(this.text, this.cs, {this.icon});

  final String text;
  final ColorScheme cs;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(text.toUpperCase(),
                  style: ProfileTheme.sectionLabel(cs)),
            ),
            if (icon != null)
              Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      );
}
