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

  testWidgets('открытый пин', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 860));
    final theme = AppThemes.byIndex(0);
    final cs = theme.scheme ?? ColorScheme.fromSeed(seedColor: theme.primary);

    Widget ib(IconData icon, {bool active = false}) => Container(
          width: 52,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(icon,
              size: 24,
              color: active ? cs.onSecondaryContainer : cs.onSurface),
        );

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: Stack(children: [
              Column(children: [
                // шапка: назад, автор с датой, карандаш и «ещё» группой
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.only(left: 4, right: 14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(children: [
                          CircleAvatar(
                              radius: 20,
                              backgroundColor: theme.primaryLight,
                              child: Text('А',
                                  style: TextStyle(
                                      fontFamily: 'Unbounded',
                                      fontWeight: FontWeight.w800,
                                      color: theme.textPrimary))),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Аня',
                                    style: TextStyle(
                                        fontFamily: 'Onest',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface)),
                                Text('12 сентября · 7 кадров',
                                    style: TextStyle(
                                        fontFamily: 'Onest',
                                        fontSize: 11.5,
                                        color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(24), right: Radius.circular(8)),
                      ),
                      child: Icon(Icons.edit_outlined, size: 22, color: cs.onSurface),
                    ),
                    const SizedBox(width: 2),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8), right: Radius.circular(24)),
                      ),
                      child: Icon(Icons.more_vert_rounded, size: 22, color: cs.onSurface),
                    ),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 150),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Frame(
                            aspect: 1120 / 470,
                            color: Color(0xFF6E93B8),
                            radius: 22),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: 76,
                          child: Row(children: const [
                            _Frame(aspect: 1, color: Color(0xFFB08968)),
                            SizedBox(width: 2),
                            _Frame(aspect: 0.62, color: Color(0xFF7F8C6C)),
                            SizedBox(width: 2),
                            _Frame(aspect: 0.75, color: Color(0xFFA1748C)),
                            SizedBox(width: 2),
                            _Frame(aspect: 1.5, color: Color(0xFF8899AA)),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Закат на реке',
                                  style: TextStyle(
                                      fontFamily: 'Unbounded',
                                      fontSize: 23,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                      color: cs.onSurface)),
                              const SizedBox(height: 6),
                              Text('Доехали к реке за час до заката.',
                                  style: TextStyle(
                                      fontFamily: 'Onest',
                                      fontSize: 15.5,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // блок места
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                          decoration: BoxDecoration(
                            color: cs.inverseSurface,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(children: [
                            Icon(Icons.place_rounded,
                                size: 22, color: cs.onInverseSurface),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Каменка',
                                      style: TextStyle(
                                          fontFamily: 'Onest',
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onInverseSurface)),
                                  Text('12 сентября, 19:40',
                                      style: TextStyle(
                                          fontFamily: 'Onest',
                                          fontSize: 12.5,
                                          color: cs.onInverseSurface
                                              .withValues(alpha: 0.85))),
                                ],
                              ),
                            ),
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: cs.onInverseSurface.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.near_me_rounded,
                                  size: 20, color: cs.onInverseSurface),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        // именные реакции
                        Row(children: [
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                                color: theme.bgGradient[0],
                                borderRadius: BorderRadius.circular(20)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                        ]),
                      ],
                    ),
                  ),
                ),
              ]),
              // низ: тулбар и отдельная кнопка сохранения
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: Row(children: [
                  Expanded(
                    child: Container(
                      height: 72,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(36),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          ib(Icons.favorite_rounded, active: true),
                          ib(Icons.reply_rounded),
                          ib(Icons.bookmark_border_rounded),
                          ib(Icons.push_pin_outlined),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(children: [
                    Container(
                      height: 72,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.fillColor,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(36), right: Radius.circular(10)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download_rounded,
                            size: 22,
                            color: AppThemes.onColor(theme.fillColor,
                                mode: theme.brightness)),
                        const SizedBox(width: 8),
                        Text('7',
                            style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppThemes.onColor(theme.fillColor,
                                    mode: theme.brightness))),
                      ]),
                    ),
                    const SizedBox(width: 2),
                    Container(
                      width: 46,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.fillColor,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(10), right: Radius.circular(36)),
                      ),
                      child: Icon(Icons.arrow_drop_down_rounded,
                          color: AppThemes.onColor(theme.fillColor,
                              mode: theme.brightness)),
                    ),
                  ]),
                ]),
              ),
            ]),
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
      File('${dir.path}/detail.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
    });
  });

  testWidgets('экран записи', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1040));
    final theme = AppThemes.byIndex(0);
    final cs = theme.scheme ?? ColorScheme.fromSeed(seedColor: theme.primary);

    Widget round(IconData icon, {double size = 64, BorderRadius? radius}) =>
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: radius ?? BorderRadius.circular(size / 2),
          ),
          child: Icon(icon, size: size > 56 ? 26 : 22, color: cs.onSurface),
        );

    Widget row({
      required IconData icon,
      required String label,
      required String value,
      bool key0 = false,
      bool first = false,
      bool last = false,
      bool chevron = false,
      bool? toggle,
    }) {
      final bg = key0 ? cs.secondaryContainer : cs.surfaceContainerHigh;
      final fg = key0 ? cs.onSecondaryContainer : cs.onSurface;
      final sub = key0
          ? cs.onSecondaryContainer.withValues(alpha: 0.8)
          : cs.onSurfaceVariant;
      return Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(first ? 28 : 8),
            bottom: Radius.circular(last ? 28 : 8),
          ),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: key0 ? theme.fillColor : cs.surface, shape: BoxShape.circle),
            child: Icon(icon,
                size: 22, color: key0 ? AppThemes.onColor(theme.fillColor, mode: theme.brightness) : cs.onSurface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: sub)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: key0 ? 17 : 16,
                        fontWeight: key0 ? FontWeight.w700 : FontWeight.w600,
                        color: fg)),
              ],
            ),
          ),
          if (toggle != null)
            Switch(value: toggle, onChanged: (_) {})
          else if (chevron)
            Icon(Icons.chevron_right_rounded, color: sub),
        ]),
      );
    }

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: cs, useMaterial3: true),
        home: Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: Column(children: [
              // шапка: крестик и сводка «Черновик · N кадров»
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Row(children: [
                  round(Icons.close_rounded, size: 48),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: theme.fillColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text('Черновик · 7 кадров',
                            style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                      ]),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(children: [
                        const _Frame(
                            aspect: 1120 / 470,
                            color: Color(0xFF6E93B8),
                            radius: 22),
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: Container(
                            height: 30,
                            padding: const EdgeInsets.only(left: 9, right: 12),
                            decoration: BoxDecoration(
                                color: theme.fillColor,
                                borderRadius: BorderRadius.circular(15)),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_rounded,
                                      size: 16, color: AppThemes.onColor(theme.fillColor, mode: theme.brightness)),
                                  const SizedBox(width: 5),
                                  Text('Обложка',
                                      style: TextStyle(
                                          fontFamily: 'Onest',
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppThemes.onColor(theme.fillColor, mode: theme.brightness))),
                                ]),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: cs.inverseSurface, shape: BoxShape.circle),
                            child: Icon(Icons.close_rounded,
                                size: 20, color: cs.onInverseSurface),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 132,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                          Container(
                            width: 92,
                            height: 132,
                            decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(8)),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_rounded,
                                      size: 28, color: cs.onSecondaryContainer),
                                  const SizedBox(height: 4),
                                  Text('Добавить',
                                      style: TextStyle(
                                          fontFamily: 'Onest',
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSecondaryContainer)),
                                ]),
                          ),
                          const SizedBox(width: 2),
                          const _Frame(aspect: 1, color: Color(0xFFB08968)),
                          const SizedBox(width: 2),
                          const _Frame(aspect: 0.62, color: Color(0xFF7F8C6C)),
                          const SizedBox(width: 2),
                          const _Frame(aspect: 1.5, color: Color(0xFF8899AA)),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.touch_app_outlined,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                  'Плюс слева добавляет кадры, касание ставит обложкой, долгое — убирает из записи',
                                  style: TextStyle(
                                      fontFamily: 'Onest',
                                      fontSize: 13,
                                      color: cs.onSurfaceVariant)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      row(
                          icon: Icons.title_rounded,
                          label: 'Название',
                          value: 'Закат на реке',
                          key0: true,
                          first: true),
                      const SizedBox(height: 4),
                      row(
                          icon: Icons.edit_note_rounded,
                          label: 'Подпись',
                          value: 'Доехали к реке за час до заката.',
                          key0: true),
                      const SizedBox(height: 4),
                      row(
                          icon: Icons.calendar_today_rounded,
                          label: 'Дата съёмки',
                          value: '12 сентября 2026',
                          chevron: true),
                      const SizedBox(height: 4),
                      row(
                          icon: Icons.place_rounded,
                          label: 'Место',
                          value: 'Каменка',
                          chevron: true),
                      const SizedBox(height: 4),
                      row(
                          icon: Icons.visibility_off_rounded,
                          label: '18+',
                          value: 'Выключено',
                          last: true,
                          toggle: false),
                    ],
                  ),
                ),
              ),
              // низ: галерея и камера парой, затем «Сохранить»
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(children: [
                  round(Icons.add_photo_alternate_rounded,
                      radius: const BorderRadius.horizontal(
                          left: Radius.circular(32), right: Radius.circular(10))),
                  const SizedBox(width: 2),
                  round(Icons.photo_camera_rounded,
                      radius: const BorderRadius.horizontal(
                          left: Radius.circular(10), right: Radius.circular(32))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: theme.fillColor,
                          borderRadius: BorderRadius.circular(32)),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded,
                                size: 22, color: AppThemes.onColor(theme.fillColor, mode: theme.brightness)),
                            const SizedBox(width: 8),
                            Text('Сохранить',
                                style: TextStyle(
                                    fontFamily: 'Onest',
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppThemes.onColor(theme.fillColor, mode: theme.brightness))),
                          ]),
                    ),
                  ),
                ]),
              ),
            ]),
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
      File('${dir.path}/form.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
    });
  });
}
