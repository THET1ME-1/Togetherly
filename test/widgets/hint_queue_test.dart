import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/hint_queue.dart';
import 'package:love_app/services/ui_prefs.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/common/hint_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Подсказок о новых функциях несколько, и показывать их разом нельзя: три
/// пузыря на одном экране — завал, а не объяснение. Очередь ведёт их по одной,
/// следующая начинается после закрытия предыдущей, и каждая гаснет навсегда.
void main() {
  late AppTheme theme;
  late GlobalKey first;
  late GlobalKey second;

  setUp(() {
    HintQueue.instance.reset();
    SharedPreferences.setMockInitialValues({});
    theme = buildAppTheme(kPalettes[3], Brightness.light);
    first = GlobalKey();
    second = GlobalKey();
  });

  Widget host() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(key: first, width: 60, height: 60),
            SizedBox(key: second, width: 60, height: 60),
          ],
        ),
      ),
    ),
  );

  void enqueueBoth(BuildContext context) {
    HintQueue.instance.enqueue(
      context: context,
      key: 'first_hint',
      targetKey: first,
      text: 'Первая подсказка',
      gotIt: 'Понятно',
      icon: Icons.videocam_rounded,
      theme: theme,
    );
    HintQueue.instance.enqueue(
      context: context,
      key: 'second_hint',
      targetKey: second,
      text: 'Вторая подсказка',
      gotIt: 'Понятно',
      icon: Icons.favorite_rounded,
      theme: theme,
      side: HintSide.below,
    );
  }

  testWidgets('вторая ждёт, пока не закроют первую', (tester) async {
    await tester.pumpWidget(host());
    enqueueBoth(tester.element(find.byKey(first)));
    await tester.pumpAndSettle();

    expect(find.text('Первая подсказка'), findsOneWidget);
    expect(find.text('Вторая подсказка'), findsNothing);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Первая подсказка'), findsNothing);
    expect(find.text('Вторая подсказка'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(Overlay), findsWidgets);
    expect(find.text('Вторая подсказка'), findsNothing);
  });

  testWidgets('показанная подсказка не возвращается', (tester) async {
    await tester.pumpWidget(host());
    enqueueBoth(tester.element(find.byKey(first)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Второй заход на экран: обе уже отмечены, показывать нечего.
    enqueueBoth(tester.element(find.byKey(first)));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Первая подсказка'), findsNothing);
    expect(find.text('Вторая подсказка'), findsNothing);
    expect(await UiPrefs.hintSeen('first_hint'), isTrue);
    expect(await UiPrefs.hintSeen('second_hint'), isTrue);
  });

  testWidgets('найденный самим жест снимает свою подсказку', (tester) async {
    await tester.pumpWidget(host());
    await HintQueue.instance.markSeen('first_hint');

    enqueueBoth(tester.element(find.byKey(first)));
    await tester.pumpAndSettle();

    // Первая погашена заранее — сразу показывается вторая.
    expect(find.text('Первая подсказка'), findsNothing);
    expect(find.text('Вторая подсказка'), findsOneWidget);

    // Закрываем: пока пузырь висит, у него тикает таймер жизни.
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('тап мимо закрывает и пускает следующую', (tester) async {
    await tester.pumpWidget(host());
    enqueueBoth(tester.element(find.byKey(first)));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Вторая подсказка'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('подсказка про боковую кнопку помнит старый ключ', (
    tester,
  ) async {
    // Ключ существовал до очереди; сменить его значило бы показать подсказку
    // заново всем, кто её уже видел.
    SharedPreferences.setMockInitialValues({UiPrefs.kSideActionHintSeen: true});

    expect(await UiPrefs.hintSeen('side_action'), isTrue);
    expect(UiPrefs.hintKey('side_action'), UiPrefs.kSideActionHintSeen);
    expect(UiPrefs.hintKey('snap_hold'), 'hint_snap_hold_seen');
  });
}
