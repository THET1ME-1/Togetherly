import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_date.dart';
import 'package:love_app/models/symbol_catalog.dart';
import 'package:love_app/screens/dates/date_form_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/dates/next_date_card.dart';
import 'package:love_app/widgets/dates/phone_calendar_sheet.dart';
import 'package:love_app/widgets/dates/reminder_sheet.dart';
import 'package:love_app/widgets/dates/repeat_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Наши даты» на глаз (TOG-61). В общий прогон не входит:
/// `flutter test test/goldens/dates_preview.dart`, снимки в `build/dates/`.
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    any = true;
  }
  if (any) await loader.load();
}

PairDate _date(Map<String, dynamic> m) => PairDate.fromMap({
      'id': 'd1',
      'author_uid': 'her',
      'title': 'Концерт в «Арене»',
      'symbol': 'theater_comedy',
      'day': '2026-12-04',
      'start_time': '19:00',
      'tz': 'Europe/Moscow',
      'rrule': '',
      'reminders': [60, 1440],
      ...m,
    });

void main() {
  setUpAll(() async {
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache'
          '/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    await _loadFont('MaterialSymbolsRounded', ['assets/fonts/MaterialSymbolsRounded.ttf']);
  });

  testWidgets('наши даты', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    await tester.runAsync(SymbolCatalog.load);

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> shot(String name, Size size, Brightness b, Widget Function(ColorScheme cs) build) async {
      await tester.binding.setSurfaceSize(size);
      final theme = buildAppTheme(kPalettes[0], b);
      final cs = ProfileTheme.schemeFor(theme);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.data(cs),
        home: RepaintBoundary(key: key, child: build(cs)),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final dir = Directory('build/dates')..createSync(recursive: true);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    final now = DateTime(2026, 11, 28, 12);
    final concert = _date({});
    final first = _date({
      'id': 'f',
      'title': 'Первое свидание',
      'symbol': 'favorite',
      'day': '2025-11-08',
      'start_time': '',
      'rrule': 'FREQ=YEARLY',
      'reminders': [-540, 900],
      'author_uid': 'me',
    });
    final auto = autoDates(
      start: DateTime(2024, 12, 10),
      birthdays: {'her': DateTime(2000, 1, 17)},
      myUid: 'me',
      names: const {'her': 'Лиза'},
    );
    final upcoming = upcomingOccurrences([concert, first, ...auto], now);

    for (final b in Brightness.values) {
      await shot('header_${b.name}', const Size(390, 460), b, (cs) {
        return Scaffold(
          backgroundColor: b == Brightness.light ? const Color(0xFFF2F2F4) : cs.surface,
          body: Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: NextDateCard(
                  occurrence: upcoming.first,
                  scheme: cs,
                  now: now,
                  line: '4 декабря, пятница · 19:00 · добавила Лиза',
                  onTap: () {},
                ),
              ),
              const SizedBox(height: 12),
              UpcomingDatesRow(occurrences: upcoming.skip(1).take(3).toList(), scheme: cs, onOpen: (_) {}, onAll: () {}),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: EmptyDatesCard(scheme: cs, onAdd: () {}),
              ),
            ],
          ),
        );
      });
    }

    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    await shot('form_new', const Size(390, 1000), Brightness.light,
        (cs) => DateFormScreen(theme: theme, groupId: 'g', initialDay: DateTime(2025, 11, 8)));
    await shot('form_timed', const Size(390, 1000), Brightness.light,
        (cs) => DateFormScreen(theme: theme, groupId: 'g', existing: concert, occurrenceDay: DateTime(2026, 12, 4)));
    await shot('form_new_320', const Size(320, 900), Brightness.light,
        (cs) => MediaQuery(
              data: const MediaQueryData(size: Size(320, 900), textScaler: TextScaler.linear(1.3)),
              child: DateFormScreen(theme: theme, groupId: 'g', initialDay: DateTime(2026, 11, 26)),
            ));

    Widget sheet(ColorScheme cs, Widget child) => Scaffold(
          backgroundColor: const Color(0xFFA3A3A5),
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: cs.surfaceContainerLow,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: child,
            ),
          ),
        );

    await shot('repeat_custom', const Size(390, 844), Brightness.light, (cs) => sheet(
          cs,
          CustomRepeatSheet(
            theme: theme,
            scheme: cs,
            start: DateTime(2026, 11, 8),
            current: 'FREQ=WEEKLY;BYDAY=WE,SU;UNTIL=20261215',
          ),
        ));
    await shot('repeat_custom_month', const Size(390, 844), Brightness.light, (cs) => sheet(
          cs,
          CustomRepeatSheet(theme: theme, scheme: cs, start: DateTime(2026, 11, 26), current: 'FREQ=MONTHLY;BYDAY=-1TH'),
        ));
    await shot('reminder_custom_timed', const Size(390, 700), Brightness.light, (cs) => sheet(
          cs,
          CustomReminderSheet(theme: theme, scheme: cs, allDay: false, nextStart: DateTime(2026, 12, 4, 19)),
        ));
    await shot('reminder_custom_allday', const Size(390, 700), Brightness.light, (cs) => sheet(
          cs,
          CustomReminderSheet(theme: theme, scheme: cs, allDay: true, nextStart: DateTime(2026, 12, 4)),
        ));
    await shot('phone_calendar', const Size(390, 600), Brightness.light,
        (cs) => sheet(cs, PhoneCalendarSheet(scheme: cs)));
  });
}
