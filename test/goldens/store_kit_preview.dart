import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/doing.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/mood_vessel.dart';
import 'package:love_app/models/together_milestones.dart';
import 'package:love_app/screens/miss_you_screen.dart' show vibeIcon;
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/widget_theme_sync.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/doing/doing_rooms.dart';
import 'package:love_app/widgets/miss_widget_card.dart';
import 'package:love_app/widgets/miss_you/vibe_chip.dart';
import 'package:love_app/widgets/mood/mood_vessel.dart';
import 'package:love_app/widgets/petal_timer_dial.dart';
import 'package:love_app/widgets/together_track_card.dart';
import 'package:love_app/widgets/year_ring_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Кружок с буквой вместо фото: на скриншотах магазина чужих лиц нет.
Widget _face(String initial, Color bg, Color fg) => Container(
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(fontFamily: 'Onest', fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );

/// Месяц настроений для сосуда: те же правила, что в превью сосуда.
List<VesselDay> _month() {
  const moods = [Color(0xFFFF7E8B), Color(0xFFFFB05C), Color(0xFF7C6CF0), Color(0xFF4CC38A), Color(0xFF3B82F6)];
  final rnd = math.Random(7);
  return [
    for (var d = 1; d <= 31; d++)
      () {
        final roll = rnd.nextInt(10);
        final kinds = <MemoryType>[
          for (var i = 0; i < rnd.nextInt(4); i++) MemoryType.values[rnd.nextInt(MemoryType.values.length)],
        ];
        return VesselDay(
          date: DateTime(2026, 10, d),
          mineMood: roll > 1 ? moods[rnd.nextInt(moods.length)] : null,
          partnerMood: roll > 3 ? moods[rnd.nextInt(moods.length)] : null,
          intimacy: roll == 9,
          memories: kinds,
          chatted: roll > 4,
        );
      }(),
  ];
}

/// Детали приложения для скриншотов Google Play: настоящие виджеты из кода в
/// розовой теме (палитра 0), крупно и на прозрачном фоне, чтобы собирать из
/// них композицию. В общий прогон не входит:
/// `flutter test test/goldens/store_kit_preview.dart`, картинки в
/// `build/store-kit/`. Рисунков Ту в комнатках нет — каталог в тесте пуст,
/// кадры кладутся поверх при сборке баннера.
Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(f.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  // Шрифты — до теста: чтение файла внутри testWidgets идёт в ненастоящем
  // времени и не завершается никогда.
  setUpAll(() async {
    await _font('Onest', 'assets/fonts/Onest.ttf');
    await _font('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _font(
      'MaterialIcons',
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
  });

  testWidgets('детали для скриншотов магазина', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Только розовая тема: на скриншотах магазина одна палитра.
    final appTheme = buildAppTheme(kPalettes[0], Brightness.light);
    final theme = ProfileTheme.themeFor(appTheme);
    final now = DateTime(2026, 11, 11, 19, 40);

    Future<void> shot(String name, Size size, Widget child) async {
      await tester.binding.setSurfaceSize(size);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Material(
          type: MaterialType.transparency,
          child: Center(child: RepaintBoundary(key: key, child: child)),
        ),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final dir = Directory('build/store-kit')..createSync(recursive: true);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 4);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    // Вместе год и три месяца: лепестки заполнены по-разному.
    await shot(
      'petal',
      const Size(360, 360),
      SizedBox(
        width: 340,
        height: 340,
        child: PetalTimerDial(theme: appTheme, startDate: DateTime(2025, 8, 4, 8, 15)),
      ),
    );

    // Обе комнатки в розовых ролях темы.
    await shot(
      'rooms',
      const Size(393, 220),
      SizedBox(
        width: 377,
        child: DoingRooms(
          now: now,
          my: DoingRoomLook(wall: theme.colorScheme.primaryContainer, doing: Doing.of('sleep', now)),
          partner: DoingRoomLook(wall: theme.colorScheme.secondaryContainer, doing: Doing.of('movie', now)),
        ),
      ),
    );
    final cs = theme.colorScheme;
    final roles = WidgetThemeSync.rolesOf(cs);
    final s = LocaleService.current;

    // «Скучаю» — карточка виджета, как в каталоге.
    await shot(
      'miss',
      const Size(360, 180),
      SizedBox(
        width: 338,
        height: 158,
        child: MissWidgetCard(
          size: MissCardSize.medium,
          myCount: 128,
          partnerCount: 131,
          roles: roles,
          meLabel: s.tgMissMe,
          partnerName: 'Аня',
          sendLabel: s.tgMissTitle,
          whenLabel: s.tgMissToday,
          myFace: _face('М', roles['avatarMine']!, roles['onPrimaryContainer']!),
          partnerFace: _face('А', roles['avatarPartner']!, roles['onTertiaryContainer']!),
        ),
      ),
    );

    // «Вместе» с вехами — большой размер.
    final start = DateTime(2025, 8, 4);
    final track = milestoneTrack(start: start, today: DateTime(2026, 11, 11));
    final labels = trackLabels(track, s, s.dayLogDate);
    await shot(
      'together',
      const Size(360, 360),
      SizedBox(
        width: 338,
        height: 338,
        child: TogetherTrackCard(
          size: TogetherCardSize.large,
          days: track.days,
          daysLabel: s.tgDaysTogetherCaption(track.days),
          percent: track.percent,
          roles: roles,
          startDate: 'С ${s.dayLogDate(start)} ${start.year}',
          names: 'Миша + Аня',
          previousTitle: labels.previousTitle,
          previousSub: labels.previousSub,
          todayTitle: labels.todayTitle,
          todaySub: labels.todaySub,
          nextTitle: labels.nextTitle,
          nextSub: labels.nextSub,
          anniversaryTitle: labels.anniversaryTitle,
          anniversarySub: labels.anniversarySub,
          myAvatar: _face('М', roles['avatarMine']!, roles['onPrimaryContainer']!),
          partnerAvatar: _face('А', roles['avatarPartner']!, roles['onTertiaryContainer']!),
        ),
      ),
    );

    // «Кольцо года» 4×2.
    await shot(
      'ring',
      const Size(440, 220),
      SizedBox(
        width: 424,
        height: 200,
        child: YearRingCard(
          small: false,
          colors: YearRingColors(primary: cs.primary, onPrimary: cs.onPrimary, tertiaryContainer: cs.tertiaryContainer),
          texts: const YearRingTexts(
            daysCaption: 'Дней вместе',
            untilAnniversary: 'До годовщины',
            daysLeftUnit: 'дней',
            anniversaryLine: 'Годовщина 4 августа',
            monthsShort: 'мес.',
            memoriesUnit: 'воспоминаний',
            smallLine: 'Ещё 266 дней',
          ),
          daysTotal: 464,
          daysLeft: 266,
          months: 15,
          memories: 212,
          progress: 99 / 365,
        ),
      ),
    );

    // Плитки импульсов «Скучаю»: как на экране «Скучаю».
    for (final (name, type, label) in [
      ('vibe_think', 'thinking_of_you', 'Думаю о тебе'),
      ('vibe_hug', 'want_hug', 'Хочу обнять'),
    ]) {
      await shot(
        name,
        const Size(220, 120),
        Theme(
          data: ProfileTheme.data(cs),
          child: SizedBox(
            width: 200,
            child: VibeChip(scheme: cs, icon: vibeIcon(type), label: label, mine: 64, partner: 71, onTap: () {}),
          ),
        ),
      );
    }

    // Сосуд настроений за месяц.
    await shot(
      'vessel',
      const Size(393, 380),
      SizedBox(width: 353, child: MoodVessel(days: _month(), columns: 6, height: 320, previousLevel: 9)),
    );
    stdout.writeln('детали: build/store-kit/');
  });
}
