import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ailment.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/screens/home/widgets/mood_picker_dialog.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Раскладка листа настроения на узком экране: подписи в пять колонок не должны
/// переполнять ячейку, иначе нижний ряд начнёт резаться, как было в старой сетке.
Widget _sheet({bool ailmentTab = true, bool onAilment = false}) {
  final t = buildAppTheme(kPalettes[1], Brightness.light);
  return MediaQuery(
    data: const MediaQueryData(size: Size(360, 760)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: t,
        child: MaterialApp(
          theme: ProfileTheme.themeFor(t),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 620,
                child: MoodPickerSheet(
                  scrollController: ScrollController(),
                  currentEmoji: MoodOption.all[1].imagePath,
                  primary: t.primary,
                  title: 'Как вы себя чувствуете?',
                  subtitle: 'Партнёр увидит ваше настроение',
                  onSelect: (_) {},
                  onClear: () async {},
                  showAilmentTab: ailmentTab,
                  ailmentOnly: onAilment,
                  currentAilmentId: 'cold',
                  onSelectAilment: (_) {},
                  onClearAilment: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('сетка настроений рисуется без переполнения', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet());
    await tester.pump();

    final s = LocaleService.current;
    expect(find.text(s.moodBandBright), findsOneWidget);
    expect(find.text(s.moodBandEven), findsOneWidget);
    expect(find.text(s.clearMood), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('вкладка самочувствия показывает чипы', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(ailmentTab: false, onAilment: true));
    await tester.pump();

    final s = LocaleService.current;
    expect(find.text(kAilments.first.localizedLabel), findsOneWidget);
    expect(find.text(s.clearAilment), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
