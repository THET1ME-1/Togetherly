// Тесты для пары: прохождение целиком, общий итог, когда партнёр уже прошёл,
// и подсказка ждать, когда ещё нет. Узкий экран и крупный шрифт без
// переполнений.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_quiz.dart';
import 'package:love_app/screens/pair_quiz_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pair_quiz_service.dart';
import 'package:love_app/theme/profile_theme.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B));

  Future<void> pump(WidgetTester t, Widget child, {double width = 320}) async {
    t.view.physicalSize = Size(width * 3, 760 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ProfileTheme.data(cs),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 760), textScaler: const TextScaler.linear(1.3)),
        child: child,
      ),
    ));
    await t.pump();
  }

  for (final kind in QuizKind.values) {
    testWidgets('${kind.name}: пройти до конца, партнёр уже прошёл', (t) async {
      final partner = scoreQuiz(kind, List.filled(15, 1));
      await pump(
        t,
        PairQuizScreen(
          kind: kind,
          scheme: cs,
          groupId: 'g',
          myUid: 'me',
          partnerName: 'Маша',
          initial: PairQuizResults(theirs: {kind: partner}),
        ),
      );
      expect(find.text('Начать'), findsOneWidget);
      await t.tap(find.text('Начать'));
      await t.pump();
      final n = quizQuestions(kind, 'ru').length;
      for (var i = 0; i < n; i++) {
        expect(find.text('Вопрос ${i + 1} из $n'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('quiz_option_0')));
        await t.pump();
      }
      if (kind == QuizKind.alike) {
        // Оба ответили — карточка «Ответы готовы» с обещанием, что партнёру
        // «достанутся те же вопросы», врала бы: итог целиком в «Вместе»
        // (замечено на эмуляторе 08.11.2026).
        expect(find.text('Ответы готовы'), findsNothing);
        // Вопросы взяты у партнёра, поэтому сравниваются все пятнадцать.
        await t.scrollUntilVisible(find.textContaining('из 15'), 200);
        expect(find.textContaining('%'), findsOneWidget);
      } else {
        expect(find.text('Ваш результат'), findsOneWidget);
        await t.scrollUntilVisible(find.text('Маша'), 200);
        expect(find.text('Маша'), findsOneWidget);
      }
      await t.scrollUntilVisible(find.text('ВМЕСТЕ'), 200);
      expect(find.text('ВМЕСТЕ'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('экран тестов: «Умение любить» первым, за ним пять новых', (t) async {
    var loveOpened = false;
    await pump(
      t,
      PairTestsScreen(
        scheme: cs,
        groupId: 'g',
        myUid: 'me',
        partnerName: 'Маша',
        loveTestBuilder: (_) {
          loveOpened = true;
          return const Scaffold(body: Text('умение любить'));
        },
        initial: PairQuizResults(mine: {QuizKind.lang: scoreQuiz(QuizKind.lang, List.filled(15, 0))}),
      ),
    );
    final love = t.getTopLeft(find.text('Умение любить'));
    expect(love.dy, lessThan(t.getTopLeft(find.text('Язык любви')).dy));
    expect(find.text('Тип привязанности'), findsOneWidget);
    expect(find.text('Какое ты животное'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Насколько вы похожи'), 200);
    expect(find.text('Как вы ссоритесь'), findsOneWidget);
    expect(find.text('Насколько вы похожи'), findsOneWidget);
    await t.drag(find.byType(ListView), const Offset(0, 2000));
    await t.pumpAndSettle();
    expect(find.text('Пройден'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Умение любить'));
    await t.pumpAndSettle();
    expect(loveOpened, isTrue);
  });

  testWidgets('партнёр не прошёл — ждём его', (t) async {
    await pump(
      t,
      PairQuizScreen(
        kind: QuizKind.animal,
        scheme: cs,
        groupId: 'g',
        myUid: 'me',
        initial: PairQuizResults(mine: {QuizKind.animal: scoreQuiz(QuizKind.animal, List.filled(15, 3))}),
      ),
    );
    expect(find.textContaining('Партнёр ещё не прошёл'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Пройти заново'), 200);
    expect(find.text('Поделиться'), findsOneWidget);
    expect(find.text('Пройти заново'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
