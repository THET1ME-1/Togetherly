import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/feedback.dart';
import 'package:love_app/screens/feedback_screen.dart';

/// Обращение прямо из приложения.
///
/// Google Play отклонил 1.42 (11.11.2026) по правилам о безопасности детей:
/// человек обязан иметь возможность сообщить о проблеме, не выходя из
/// приложения. У нас поддержка открывала почтовую программу, а «Написать нам»
/// уводило в Telegram. Проверяющий такой формы не нашёл, и был прав.
void main() {
  group('правила формы', () {
    test('текст короче десяти знаков не отправляется', () {
      expect(feedbackReady('коротко'), isFalse);
      expect(feedbackReady('          '), isFalse);
      expect(feedbackReady('Не открывается лента'), isTrue);
    });

    test('предел длины — как на сервере', () {
      expect(feedbackReady('я' * kFeedbackMax), isTrue);
      expect(feedbackReady('я' * (kFeedbackMax + 1)), isFalse);
    });

    test('виды обращений называются так же, как их ждёт сервер', () {
      final hook =
          File('pocketbase/pb_hooks/feedback_mail.js').readAsStringSync();
      for (final kind in FeedbackKind.values) {
        expect(hook, contains('${kind.wire}:'), reason: kind.wire);
      }
      expect(FeedbackKind.childSafety.wire, 'child_safety');
    });

    test('ответ сервера переводится в понятный итог', () {
      expect(feedbackSentOf(200), FeedbackSent.ok);
      expect(feedbackSentOf(429), FeedbackSent.tooMany);
      expect(feedbackSentOf(500), FeedbackSent.failed);
      expect(feedbackSentOf(null), FeedbackSent.failed);
    });
  });

  group('экран', () {
    Future<void> open(
      WidgetTester tester, {
      required Future<FeedbackSent> Function(FeedbackKind, String) send,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: FeedbackScreen(
          scheme: ColorScheme.fromSeed(seedColor: Colors.pink),
          accountEmail: 'person@example.com',
          send: send,
        ),
      ));
    }

    testWidgets('человек выбирает вид, пишет и отправляет, не выходя из экрана',
        (tester) async {
      FeedbackKind? sentKind;
      String? sentText;
      await open(tester, send: (kind, text) async {
        sentKind = kind;
        sentText = text;
        return FeedbackSent.ok;
      });

      // Пока текста нет, кнопка не отправляет.
      await tester.tap(find.byKey(const Key('feedback_send')));
      await tester.pump();
      expect(sentKind, isNull);

      await tester.tap(find.byKey(const Key('feedback_kind_child_safety')));
      await tester.enterText(
          find.byKey(const Key('feedback_text')), 'В чате недопустимое фото');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('feedback_send')));
      await tester.tap(find.byKey(const Key('feedback_send')));
      await tester.pumpAndSettle();

      expect(sentKind, FeedbackKind.childSafety);
      expect(sentText, 'В чате недопустимое фото');
      expect(find.text(trKey('fb.sentTitle')), findsOneWidget,
          reason: 'человек видит, что обращение получено');
    });

    testWidgets('сервер отказал — текст остаётся, человек видит причину',
        (tester) async {
      await open(tester, send: (kind, text) async => FeedbackSent.failed);
      await tester.enterText(
          find.byKey(const Key('feedback_text')), 'Не открывается лента');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('feedback_send')));
      await tester.tap(find.byKey(const Key('feedback_send')));
      await tester.pumpAndSettle();

      expect(find.text(trKey('fb.errFailed')), findsOneWidget);
      expect(find.text('Не открывается лента'), findsOneWidget,
          reason: 'написанное не должно пропасть');
      expect(find.text(trKey('fb.sentTitle')), findsNothing);
    });

    testWidgets('безопасность детей выбирается отдельным видом', (tester) async {
      await open(tester, send: (kind, text) async => FeedbackSent.ok);
      expect(find.text(trKey('fb.kindChild')), findsOneWidget);
      await tester.tap(find.byKey(const Key('feedback_kind_child_safety')));
      await tester.pump();
      expect(find.text(trKey('fb.childNote')), findsOneWidget);
    });
  });

  group('подключено', () {
    test('обращение уходит на сервер, а не в почту и не в Telegram', () {
      final screen =
          File('lib/screens/feedback_screen.dart').readAsStringSync();
      final service =
          File('lib/services/feedback_service.dart').readAsStringSync();
      for (final source in [screen, service]) {
        expect(source, isNot(contains('launchUrl')));
        expect(source, isNot(contains('mailto:')));
        expect(source, isNot(contains('t.me/')));
      }
      expect(service, contains("'/api/feedback'"));
    });

    test('вход в форму есть в настройках и в справке', () {
      final settings =
          File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(settings, contains("trKey('fb.row')"));
      expect(settings, contains('onFeedback'));
      final profile =
          File('lib/screens/profile_screen.dart').readAsStringSync();
      expect(profile, contains('onFeedback: () => _openFeedback(ctx)'));
      expect(profile, contains('onWriteUs: () => _openFeedback(context)'),
          reason: '«Написать нам» в справке открывает форму, а не Telegram');
    });

    test('каждая строка формы есть на всех девяти языках', () {
      final dict = File('lib/l10n/dict/feedback.dart').readAsStringSync();
      final uk = File('lib/l10n/uk/feedback.dart').readAsStringSync();
      final zh = File('lib/l10n/zh/feedback.dart').readAsStringSync();
      final keys = RegExp(r"^  '(fb\.[A-Za-z]+)': \{", multiLine: true)
          .allMatches(dict)
          .map((m) => m.group(1)!)
          .toList();
      expect(keys.length, greaterThanOrEqualTo(18));
      for (final key in keys) {
        final line = RegExp("^  '${RegExp.escape(key)}': \\{(.*)\\},\$",
                multiLine: true)
            .firstMatch(dict)!
            .group(1)!;
        for (final lang in ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de']) {
          expect(line, contains("'$lang': "), reason: '$key: нет $lang');
        }
        expect(uk, contains("'$key': "), reason: '$key: нет украинского');
        expect(zh, contains("'$key': "), reason: '$key: нет китайского');
      }
    });
  });
}
