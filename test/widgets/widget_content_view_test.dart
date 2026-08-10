import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/widgets/widget_content_view.dart';

/// Содержимое парного виджета открывается целиком.
///
/// Карточка на экране виджетов рисует строку с многоточием, и до этих листов
/// длинное сообщение партнёра дочитать было негде: половина партнёра не
/// отвечала на нажатие вовсе. Тест держит именно это — текст доезжает без
/// обрезки, а песня без обложки не остаётся без названия.
const _longMessage =
    'Люблю тебя. Сегодня в универе было тяжело, но я вспоминала, как мы '
    'вчера гуляли у реки, и становилось легче. Приеду поздно, не жди с '
    'ужином — я купила нам мороженое.';

Widget _host(void Function(BuildContext) onTap) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onTap(context),
            child: const Text('открыть'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('письмо показывается целиком, без многоточия', (tester) async {
    await tester.pumpWidget(_host((context) => showWidgetTextSheet(
          context,
          theme: AppThemes.pink,
          title: 'Сообщение',
          text: _longMessage,
          authorUid: 'partner-uid',
          authorName: 'Ксюша',
          updatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        )));

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    final letter = tester.widget<SelectableText>(
      find.byWidgetPredicate((w) => w is SelectableText && w.data == _longMessage),
    );
    expect(letter.maxLines, isNull, reason: 'текст не должен обрезаться');
    expect(find.text('Ксюша'), findsOneWidget);
  });

  testWidgets('песня без обложки оставляет название и исполнителя',
      (tester) async {
    await tester.pumpWidget(_host((context) => showWidgetMusicSheet(
          context,
          theme: AppThemes.pink,
          title: 'No. 1 Party Anthem',
          artist: 'Arctic Monkeys',
          coverUrl: null,
          authorUid: 'partner-uid',
          authorName: 'Ксюша',
        )));

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    expect(find.text('No. 1 Party Anthem'), findsOneWidget);
    expect(find.text('Arctic Monkeys'), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });
}
