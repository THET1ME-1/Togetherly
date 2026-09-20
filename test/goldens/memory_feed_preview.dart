// Превью карточки ленты: рисует те же виджеты, что стоят в экране, и
// сохраняет PNG в build/feed-preview/. Нужен для сверки с макетом глазами —
// без сборки приложения и без эмулятора.
//
// Имя файла БЕЗ `_test`: обычный `flutter test` его не подхватывает.
// Запуск: flutter test test/goldens/memory_feed_preview.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_reaction.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/memory/media_strip.dart';

/// Кадр-заглушка нужного размера: сеть в тестах недоступна, а пропорции
/// проверить надо — их и подставляем прямо в кэш.
class _Frame extends StatelessWidget {
  const _Frame({required this.aspect, required this.color, this.radius = 8});

  final double aspect;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(aspectRatio: aspect, child: ColoredBox(color: color)),
    );
  }
}

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
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('карточка ленты', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    final theme = AppThemes.byIndex(0);
    const stripHeight = 56.0;

    Widget chip(Widget child, Color bg, {double h = 40, double pad = 12}) =>
        Container(
          height: h,
          padding: EdgeInsets.symmetric(horizontal: pad),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(h / 2)),
          alignment: Alignment.center,
          child: child,
        );

    final card = Container(
      decoration: BoxDecoration(
        color: theme.cardSurface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // шапка карточки
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.primaryLight,
                    child: Text('А',
                        style: TextStyle(
                            fontFamily: 'Unbounded',
                            fontWeight: FontWeight.w800,
                            color: theme.textPrimary))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Аня',
                          style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: theme.textPrimary)),
                      Text('12 сентября · Каменка',
                          style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 12.5,
                              color: theme.textSecondary)),
                    ],
                  ),
                ),
                chip(
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.photo_library_rounded,
                        size: 16, color: theme.textSecondary),
                    const SizedBox(width: 5),
                    Text('7',
                        style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary)),
                  ]),
                  theme.bgGradient[0],
                  h: 30,
                  pad: 9,
                ),
                const SizedBox(width: 4),
                Icon(Icons.more_vert_rounded, color: theme.textSecondary),
              ],
            ),
          ),
          // название и подпись
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Закат на реке',
                    style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary)),
                const SizedBox(height: 2),
                Text('Доехали к реке за час до заката.',
                    style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 15,
                        height: 1.35,
                        color: theme.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // обложка в своей пропорции и плёнка остальных кадров
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Frame(
                    aspect: 1120 / 470,
                    color: const Color(0xFF6E93B8),
                    radius: 22),
                const SizedBox(height: 2),
                SizedBox(
                  height: stripHeight,
                  child: Row(children: [
                    const _Frame(aspect: 1, color: Color(0xFFB08968)),
                    const SizedBox(width: 2),
                    const _Frame(aspect: 0.62, color: Color(0xFF7F8C6C)),
                    const SizedBox(width: 2),
                    const _Frame(aspect: 0.75, color: Color(0xFFA1748C)),
                    const SizedBox(width: 2),
                    const _Frame(aspect: 1.5, color: Color(0xFF8899AA)),
                    const SizedBox(width: 2),
                    FilmRestTile(
                      count: 2,
                      height: stripHeight,
                      label: 'кадра',
                      background: theme.primaryLight,
                      foreground: theme.textPrimary,
                    ),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // низ карточки: именная реакция, комментарии, сохранение
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                chip(
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.primaryLight,
                        child: Text('С',
                            style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: theme.textPrimary))),
                    const SizedBox(width: 6),
                    Icon(reactionByKey('heart').icon,
                        size: 18, color: theme.fillColor),
                  ]),
                  theme.bgGradient[0],
                  pad: 6,
                ),
                const SizedBox(width: 2),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: theme.bgGradient[0], shape: BoxShape.circle),
                  child: Icon(Icons.add_reaction_outlined,
                      size: 20, color: theme.textSecondary),
                ),
                const SizedBox(width: 6),
                chip(
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        size: 18, color: theme.textSecondary),
                    const SizedBox(width: 6),
                    Text('3',
                        style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary)),
                  ]),
                  theme.bgGradient[0],
                ),
                const Spacer(),
                Row(children: [
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.fillColor,
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(20), right: Radius.circular(6)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.download_rounded,
                          size: 19,
                          color: AppThemes.onColor(theme.fillColor,
                              mode: theme.brightness)),
                      const SizedBox(width: 6),
                      Text('7',
                          style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppThemes.onColor(theme.fillColor,
                                  mode: theme.brightness))),
                    ]),
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: 34,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.fillColor,
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(6), right: Radius.circular(20)),
                    ),
                    child: Icon(Icons.arrow_drop_down_rounded,
                        color: AppThemes.onColor(theme.fillColor,
                            mode: theme.brightness)),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: theme.bgGradient[0],
          body: SafeArea(
            child: Column(
              children: [
                // шапка экрана: назад, поиск с аватарками, «ещё»
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: theme.cardSurface, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_rounded,
                          color: theme.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.only(left: 16, right: 10),
                        decoration: BoxDecoration(
                          color: theme.cardSurface,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Row(children: [
                          Icon(Icons.search_rounded,
                              size: 21, color: theme.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Искать в воспоминаниях',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: 'Onest',
                                    fontSize: 14.5,
                                    color: theme.textSecondary)),
                          ),
                          const SizedBox(width: 6),
                          CircleAvatar(
                              radius: 16,
                              backgroundColor: theme.primaryLight,
                              child: Text('А',
                                  style: TextStyle(
                                      fontFamily: 'Unbounded',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: theme.textPrimary))),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: theme.cardSurface, shape: BoxShape.circle),
                      child: Icon(Icons.more_vert_rounded,
                          color: theme.textPrimary),
                    ),
                  ]),
                ),
                // фильтры одинаковыми чипами
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    children: [
                      for (final f in [
                        ('Всё', Icons.apps_rounded, true),
                        ('Кадры', Icons.photo_library_rounded, false),
                        ('Заметки', Icons.sticky_note_2_rounded, false),
                        ('Места', Icons.place_rounded, false),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            height: 40,
                            padding:
                                const EdgeInsets.only(left: 11, right: 14),
                            decoration: BoxDecoration(
                              color: f.$3 ? theme.fillColor : theme.cardSurface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(f.$2,
                                    size: 18,
                                    color: f.$3
                                        ? AppThemes.onColor(theme.fillColor,
                                            mode: theme.brightness)
                                        : theme.textSecondary),
                                const SizedBox(width: 6),
                                Text(f.$1,
                                    style: TextStyle(
                                        fontFamily: 'Onest',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: f.$3
                                            ? AppThemes.onColor(theme.fillColor,
                                                mode: theme.brightness)
                                            : theme.textPrimary)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: card,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/feed-preview')..createSync(recursive: true);
      File('${dir.path}/feed.png').writeAsBytesSync(
          bytes!.buffer.asUint8List(), flush: true);
    });
  });
}
