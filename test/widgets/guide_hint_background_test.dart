import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/hint_queue.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/common/guide_hint.dart';
import 'package:love_app/widgets/common/hint_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Снимок владельца 27.11.2026: на главной разом два облачка Ту с пузырями
/// (обход меню, «Связь» и «Профиль»), и «Понятно» не нажимается.
///
/// Подсказка закрывается сама через 12 с. Если в этот момент приложение
/// свёрнуто или экран погас, кадров нет, и только что вставленная запись
/// оверлея ещё не построена (`mounted == false`): прежний `close()` её не
/// убирал, но очередь считала подсказку закрытой и вставляла следующую.
/// После возврата в приложение все такие записи строились разом и висели
/// навсегда, а их «Понятно» звало уже отработавший `close()`.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HintQueue.instance.reset();
  });

  Future<GlobalKey> page(WidgetTester tester, {int targets = 1}) async {
    final keys = List.generate(targets, (_) => GlobalKey());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SizedBox(height: 300),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (final k in keys) SizedBox(key: k, width: 56, height: 56)],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    ));
    _keys = keys;
    return keys.first;
  }

  testWidgets('подсказка, истёкшая без кадров, не остаётся на экране', (tester) async {
    final target = await page(tester);
    final theme = buildAppTheme(kPalettes[0], Brightness.light);

    var finished = false;
    showGuideHint(
      tester.element(find.byKey(target)),
      targetKey: target,
      text: 'Профиль',
      gotIt: 'Понятно',
      theme: theme,
    ).then((_) => finished = true);

    // Ни одного кадра до срока: таймер срабатывает раньше, чем запись
    // оверлея построится (так бывает в свёрнутом приложении).
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(milliseconds: 100));

    expect(finished, isTrue);
    expect(find.text('Профиль'), findsNothing, reason: 'истёкшая подсказка висит поверх главной');
  });

  testWidgets('очередь в свёрнутом приложении не копит подсказки на экране', (tester) async {
    await page(tester, targets: 2);
    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    HintQueue.instance.guideOn = () => true;
    HintQueue.instance.waitCalm = (ready) async => ready();
    addTearDown(() {
      HintQueue.instance.guideOn = null;
      HintQueue.instance.waitCalm = null;
    });
    final ctx = tester.element(find.byKey(_keys[0]));
    for (final (i, text) in [(0, 'Связь'), (1, 'Профиль')]) {
      HintQueue.instance.enqueue(
        context: ctx,
        key: 'nav_test_$i',
        targetKey: _keys[i],
        text: text,
        gotIt: 'Понятно',
        icon: Icons.touch_app_rounded,
        theme: theme,
      );
    }

    // Обе подсказки истекают без единого кадра, потом приложение
    // возвращается: на экране не должно остаться ни одной зависшей.
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(milliseconds: 100));

    final shown = find.text('Связь').evaluate().length + find.text('Профиль').evaluate().length;
    expect(shown, lessThanOrEqualTo(1), reason: 'две подсказки на экране разом');

    // Видимая подсказка закрывается своей кнопкой.
    if (shown == 1) {
      await tester.tap(find.text('Понятно'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Понятно'), findsNothing, reason: '«Понятно» не закрывает подсказку');
    }
  });

  testWidgets('обычный пузырь, истёкший без кадров, тоже не остаётся', (tester) async {
    final target = await page(tester);
    final theme = buildAppTheme(kPalettes[0], Brightness.light);
    showHintBubble(
      tester.element(find.byKey(target)),
      targetKey: target,
      text: 'Пузырь',
      gotIt: 'Понятно',
      icon: Icons.touch_app_rounded,
      theme: theme,
    );
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Пузырь'), findsNothing, reason: 'истёкший пузырь висит поверх главной');
  });
}

List<GlobalKey> _keys = [];
