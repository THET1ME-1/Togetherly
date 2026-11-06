// Карточка теста для сторис: свой итог, итог партнёра и «Вместе», подпись
// Togetherly. Картинка 360×640 (×3 = 1080×1920), без переполнений при любом
// результате и без влияния крупного шрифта телефона.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_quiz.dart';
import 'package:love_app/screens/pair_quiz_story_screen.dart';
import 'package:love_app/services/locale_service.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));
  // Экран с запасом: карточка 360×640 не должна упираться в край теста.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 2400);
    view.devicePixelRatio = 3;
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B));

  for (final kind in QuizKind.values) {
    for (final type in kQuizTypes[kind]!) {
      testWidgets('${kind.name}/$type: карточка без переполнений', (t) async {
        final mine = QuizResult(kind: kind, type: type, scores: const {});
        final theirs = QuizResult(kind: kind, type: kQuizTypes[kind]!.last, scores: const {});
        await t.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800), textScaler: TextScaler.linear(1.6)),
            child: Center(
              child: PairQuizStoryCard(scheme: cs, mine: mine, theirs: theirs, partnerName: 'Маша', lang: 'ru'),
            ),
          ),
        ));
        expect(t.getSize(find.byType(PairQuizStoryCard)), const Size(360, 640));
        // У обоих один тип — название на карточке дважды.
        expect(find.textContaining(quizTypeTitle(kind, type, 'ru')), findsWidgets);
        expect(find.text('togetherly.day'), findsOneWidget);
        expect(find.textContaining('ВМЕСТЕ'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('без партнёра — только свой итог', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: PairQuizStoryCard(
          scheme: cs,
          mine: const QuizResult(kind: QuizKind.lang, type: 'touch', scores: {}),
          theirs: null,
          partnerName: '',
          lang: 'ru',
        ),
      ),
    ));
    expect(find.text('Прикосновения'), findsOneWidget);
    expect(find.textContaining('ВМЕСТЕ'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
