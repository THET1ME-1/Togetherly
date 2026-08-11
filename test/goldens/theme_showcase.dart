// Витрина тем: главная в каждой палитре, светлой и тёмной.
//
// Тем двадцать пять, на телефоне их перебирают вручную и по одной — судить о
// качестве палитры так нельзя. Здесь берутся НАСТОЯЩИЕ виджеты главной:
// лента дней с настроениями и круг «сколько мы вместе». Сам `HomeScreen`
// целиком в тест не встаёт: он поднимает уведомления, виджеты рабочего стола
// и рекламу, а их плагинов в тестовой среде нет, и живые таймеры сервисов не
// дают прогону завершиться.
//
//     flutter test test/goldens/theme_showcase.dart --update-goldens
//     python3 tools/make_theme_contact_sheet.py
//
// Это инструмент осмотра, а не проверка регрессий, поэтому имя файла БЕЗ
// `_test`: обычный `flutter test` его не подхватывает. Кадры и не могут
// совпасть дважды — круг «сколько вместе» тикает, и следующая секунда даёт
// расхождение в 700 пикселей.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/screens/expandable_timer_card.dart';
import 'package:love_app/screens/mini_mood_calendar.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/mood_service.dart';
import 'package:love_app/services/timer_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/home/daily_tasks_card.dart';

const Size _frame = Size(360, 780);

/// Один на всю витрину. `TimerService` — обычный `ChangeNotifier`, а не
/// синглтон: каждый вызов конструктора даёт ПУСТОЙ сервис, поэтому таймер,
/// заведённый в `setUpAll`, в карточку не попадал и круг показывал «Нет
/// таймеров».
final _timers = TimerService();
final _moods = MoodService();

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

/// Главная так, как её видит человек: шапка, лента дней, круг времени,
/// быстрые действия и навигация.
class _Home extends StatelessWidget {
  const _Home({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: theme.bgGradient.first,
      body: SafeArea(
        child: Column(
          children: [
            // Шапка: пара, статус и счётчик «Я скучаю» — тот же расклад.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    height: 36,
                    child: Stack(children: [
                      CircleAvatar(
                          radius: 18, backgroundColor: theme.primaryLight),
                      Positioned(
                        left: 26,
                        child: CircleAvatar(
                            radius: 18, backgroundColor: theme.primary),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.primaryLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(children: [
                      Icon(Icons.favorite_rounded,
                          size: 15, color: theme.primary),
                      const SizedBox(width: 6),
                      Text('В…',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.textPrimary)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.fillColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text('341   Я скучаю   155',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppThemes.onColor(theme.fillColor,
                                  mode: theme.brightness))),
                    ),
                  ),
                ],
              ),
            ),

            // Настоящая лента дней с отметками настроения.
            MiniMoodCalendar(moodService: _moods, theme: theme),

            // Настоящий круг «сколько мы вместе».
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    ExpandableTimerCard(
                      theme: theme,
                      timerService: _timers,
                      myAvatarUrl: '',
                      partnerAvatarUrl: '',
                      isPaired: true,
                    ),
                    const SizedBox(height: 12),
                    Theme(
                      data: ProfileTheme.data(cs),
                      child: const DailyTasksCard(
                          groupId: 'showcase', partnerName: 'Аня'),
                    ),
                  ],
                ),
              ),
            ),

            // Навигация внизу.
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: theme.primaryLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 5; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: i == 0 ? theme.navActiveBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        [
                          Icons.home_rounded,
                          Icons.widgets_rounded,
                          Icons.play_circle_rounded,
                          Icons.chat_bubble_rounded,
                          Icons.person_rounded,
                        ][i],
                        size: 20,
                        color: i == 0 ? theme.navActiveIcon : theme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialSymbolsRounded',
        ['assets/fonts/MaterialSymbolsRounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    await _loadFont('Noto Color Emoji',
        ['/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf']);

    // Пустой экран о палитре ничего не говорит: круг без таймера показывает
    // заглушку, лента дней — пустые клетки. Наполняем теми же данными, что
    // видит человек с парой.
    // `init()` тут звать НЕЛЬЗЯ: он асинхронно перечитывает prefs и присваивает
    // `_timers = []` уже после того, как таймер добавлен — круг снова показывал
    // «Нет таймеров». Заодно он лезет в облако за соло-таймерами.
    await _timers.addTimer(
      title: 'Вместе',
      startDate: DateTime.now().subtract(const Duration(days: 447)),
      emoji: '❤️',
      isDefault: true,
    );
  });

  for (final palette in kPalettes) {
    for (final brightness in Brightness.values) {
      final suffix = brightness == Brightness.light ? 'light' : 'dark';
      testWidgets('${palette.index} ${palette.name} $suffix', (tester) async {
        tester.view.physicalSize = _frame * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        final theme = buildAppTheme(palette, brightness);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ProfileTheme.data(ProfileTheme.schemeFor(theme)),
          // Анимации выключены: блоки появляются через `Future.delayed`, а
          // такой таймер не отменяется и роняет прогон уже после снимка.
          // Заодно кадр выходит собранным, а не пойманным на полпути.
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: _Home(theme: theme),
          ),
        ));
        // Лепестки набегают своим контроллером, а не через `AnimatedFoo`:
        // `disableAnimations` его не касается, и на одном кадре в секторах
        // стояли нули вместо 447 дней.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 600));
        }

        final index = palette.index.toString().padLeft(2, '0');
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('themes/$index-$suffix.png'));

        // Круг «сколько вместе» тикает раз в секунду. Снимаем дерево, чтобы
        // dispose погасил таймер: иначе прогон падает на «A Timer is still
        // pending» уже после снимка.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      });
    }
  }
}
